import Foundation
import CoreGraphics
import AppKit
import SoloCore

/// Связывает опрос экранов, политику и исполнение.
///
/// Единственный владелец состояния: остальные части приложения читают его через
/// `state` и подписываются на `onChange`.
final class Coordinator {
    static let shared = Coordinator()

    struct State {
        var displays: [DisplaySnapshot] = []
        var builtinEnabled: Bool = true
        var brightness: BrightnessLevel = .default
        var whitePoint: WhitePoint = .neutral
        var blueReduction: BlueReduction = .none
        var override: ManualOverride = .none

        /// Заглушки системы из списка исключены — показывать их пользователю
        /// как подключённый экран нельзя.
        var externals: [DisplaySnapshot] {
            displays.filter { !$0.isBuiltin && !$0.identity.isPlaceholder }
        }
    }

    private(set) var state = State()
    var onChange: (() -> Void)?
    /// Подсказка о незнакомом экране; задаётся при запуске приложения.
    var onDisplaysScanned: (([DisplaySnapshot], Set<DisplayIdentity>) -> Void)?

    let trustedDevices = TrustedDevices(storage: UserDefaultsTrustedDeviceStorage())
    let profiles = DisplayProfiles()
    /// Прежнее хранилище режимов: нужно только чтобы перенести выбор,
    /// сделанный до появления профилей.
    private let legacyModes = PreferredModes()
    /// Профиль применяется один раз на подключение, а не при каждом опросе.
    private var profileAppliedTo: Set<DisplayIdentity> = []
    private let brightness = BrightnessService()
    private let defaults = UserDefaults.standard
    private let lastBuiltinKey = "LastBuiltinDisplayID"

    /// Наши собственные вызовы тоже поднимают reconfiguration-события; без этого
    /// флага политика зациклилась бы на собственных изменениях.
    private var isApplying = false
    private var pendingRefresh: DispatchWorkItem?
    private var watchdog: Timer?
    /// Экраны, пережившие сон вместе с компьютером: автоматика к ним не
    /// применяется, пока их не переподключат или пользователь не решит явно.
    private var suppressed: Set<DisplayIdentity> = []
    private var overrideBeforeSleep: ManualOverride = .none
    private var wakeRestoreWork: DispatchWorkItem?
    /// Последняя залогированная сводка: сторожевой опрос не должен засорять лог
    /// повторами.
    private var lastLoggedSummary = ""

    private init() {}

    // MARK: Жизненный цикл

    func start() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            // Промежуточные уведомления игнорируем: интересует только результат.
            guard !flags.contains(.beginConfigurationFlag) else { return }
            Coordinator.shared.scheduleRefresh()
        }, nil)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in Coordinator.shared.scheduleRefresh() }

        startWatchdog()
        startSleepObservers()
        recoverIfStranded()
        refresh()
    }

    /// Системные уведомления об изменении конфигурации приходят не всегда:
    /// при отключении внешнего экрана событие наблюдалось потерянным. Цена
    /// пропуска — оставшийся выключенным экран, поэтому опрос идёт ещё и по
    /// таймеру.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, !self.isApplying else { return }
            self.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// Рубеж 3: приложение стартует, а встроенный экран выключен с прошлого
    /// запуска (например, после падения). Если доверенного внешнего нет —
    /// возвращаем экран немедленно.
    private func recoverIfStranded() {
        let displays = DisplayKit.onlineDisplays()
        guard !displays.contains(where: { $0.isBuiltin }) else {
            Log.state("старт: встроенный экран на месте")
            return
        }
        guard let storedID = defaults.object(forKey: lastBuiltinKey) as? NSNumber else {
            Log.state("старт: встроенный выключен, но его идентификатор неизвестен")
            return
        }

        let trusted = trustedDevices.all
        let hasTrustedExternal = displays.contains { !$0.isBuiltin && trusted.contains($0.identity) }
        Log.state("старт: встроенный выключен, доверенный внешний=\(hasTrustedExternal)")
        if !hasTrustedExternal {
            let ok = DisplayKit.setEnabled(storedID.uint32Value, true)
            Log.state("старт: возврат экрана \(storedID.uint32Value) -> \(ok)")
        }
    }

    /// Рубеж 2: восстановление при выходе из приложения.
    /// Может вызываться из любого потока, в том числе с обработчика сигнала,
    /// поэтому обходится без AppKit.
    func restoreBeforeExit() {
        Log.state("выход: восстановление")
        brightness.restoreAll()
        guard !DisplayKit.builtinIsOnline() else {
            Log.state("выход: встроенный уже включён")
            return
        }
        guard let storedID = defaults.object(forKey: lastBuiltinKey) as? NSNumber else {
            Log.state("выход: идентификатор встроенного неизвестен")
            return
        }
        let ok = DisplayKit.setEnabled(storedID.uint32Value, true)
        Log.state("выход: возврат экрана \(storedID.uint32Value) -> \(ok)")
    }

    // MARK: Реакция на изменения

    private func scheduleRefresh() {
        guard !isApplying else { return }
        pendingRefresh?.cancel()
        // Переподключение экрана порождает пачку событий; ждём, пока осядут.
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Сон и пробуждение

    private func startSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.prepareForSleep()
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.handleWake()
        }
    }

    /// Перед сном встроенный экран возвращается: если внешний после
    /// пробуждения не оживёт, изображение всё равно будет.
    private func prepareForSleep() {
        wakeRestoreWork?.cancel()
        overrideBeforeSleep = state.override
        state.override = .none
        Log.state("сон: возвращаю встроенный экран")
        if let builtinID = resolveBuiltinID(), !DisplayKit.builtinIsOnline() {
            DisplayKit.setEnabled(builtinID, true)
        }
    }

    private func handleWake() {
        // Конфигурация экранов после пробуждения устаканивается не сразу.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let externals = DisplayKit.onlineDisplays()
                .filter { !$0.isBuiltin && !$0.identity.isPlaceholder }
                .map(\.identity)
            self.suppressed = Set(externals)
            Log.state("пробуждение: автоматика подавлена для \(externals.count) экрана(ов)")
            self.refresh()

            guard WakeSettings.restoresSoloAfterWake else { return }
            let delay = WakeSettings.restoreDelaySeconds
            Log.state("пробуждение: вернусь в прежний режим через \(delay) с")
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.suppressed.removeAll()
                self.state.override = self.overrideBeforeSleep
                Log.state("пробуждение: восстанавливаю прежний режим")
                self.refresh()
            }
            self.wakeRestoreWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
        }
    }

    func refresh() {
        let displays = DisplayKit.onlineDisplays()
        if let builtin = displays.first(where: { $0.isBuiltin }) {
            defaults.set(NSNumber(value: builtin.displayID), forKey: lastBuiltinKey)
        }

        let builtinEnabled = displays.contains { $0.isBuiltin }
        // Подавление снимается, когда экран переподключили.
        let present = Set(displays.map(\.identity))
        suppressed.formIntersection(present)

        let input = PolicyInput(displays: displays,
                                builtinEnabled: builtinEnabled,
                                trusted: trustedDevices.all,
                                override: state.override,
                                suppressed: suppressed)
        let decision = Policy.decide(input)

        let summary = "экранов=\(displays.count) встроенный=\(builtinEnabled) "
            + "доверенныйВнешний=\(input.hasTrustedExternal) решение=\(decision.action.rawValue)"
        if summary != lastLoggedSummary {
            lastLoggedSummary = summary
            Log.state("опрос: " + summary)
        }
        state.displays = displays
        state.builtinEnabled = builtinEnabled
        state.override = decision.override

        onDisplaysScanned?(displays, trustedDevices.all)
        apply(decision.action)
        syncProfiles(for: displays)
        notify()
    }

    private func apply(_ action: BuiltinAction) {
        guard action != .leaveAsIs else { return }
        guard let builtinID = resolveBuiltinID() else {
            Log.state("применение \(action.rawValue): идентификатор встроенного не найден")
            return
        }

        isApplying = true
        let ok = DisplayKit.setEnabled(builtinID, action == .enable)
        Log.state("применение \(action.rawValue) к экрану \(builtinID) -> \(ok)")
        // Системе нужно время на перестройку конфигурации экранов.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.isApplying = false
            self.state.builtinEnabled = DisplayKit.onlineDisplays().contains { $0.isBuiltin }
            self.notify()
        }
    }

    /// Выключенный экран исчезает из системного списка, поэтому его идентификатор
    /// приходится помнить между вызовами.
    private func resolveBuiltinID() -> CGDirectDisplayID? {
        if let builtin = DisplayKit.builtinDisplay() { return builtin.displayID }
        return (defaults.object(forKey: lastBuiltinKey) as? NSNumber)?.uint32Value
    }

    // MARK: Профили устройства

    /// Активный профиль устройства. При первом появлении экрана профиль
    /// создаётся из прежних настроек, чтобы выбор, сделанный до появления
    /// профилей, не пропал.
    @discardableResult
    func ensureProfile(for display: DisplaySnapshot) -> DisplayProfile {
        if let active = profiles.active(for: display.identity) { return active }
        let seeded = DisplayProfile(name: "Обычный", mode: legacyModes.mode(for: display.identity))
        Log.state("создан профиль «\(seeded.name)» для «\(display.name)»")
        return profiles.add(seeded, for: display.identity)
    }

    func activeProfile(for display: DisplaySnapshot) -> DisplayProfile? {
        profiles.active(for: display.identity)
    }

    /// Выставляет настройки профиля при подключении устройства.
    ///
    /// macOS для AR-очков нередко выбирает 60 Гц, хотя устройство умеет больше,
    /// а режимы с удвоенной плотностью точек прячет целиком.
    private func syncProfiles(for displays: [DisplaySnapshot]) {
        let externals = displays.filter { !$0.isBuiltin && !$0.identity.isPlaceholder }
        profileAppliedTo.formIntersection(Set(externals.map(\.identity)))

        for display in externals where !profileAppliedTo.contains(display.identity) {
            profileAppliedTo.insert(display.identity)
            let profile = ensureProfile(for: display)
            applyMode(of: profile, to: display)
            applyTone(of: profile, to: display)
        }
        if let target = brightnessTarget, let profile = profiles.active(for: target.identity) {
            state.brightness = profile.brightnessLevel
            state.whitePoint = profile.whitePoint
            state.blueReduction = profile.blueReduction
        }
    }

    @discardableResult
    private func applyMode(of profile: DisplayProfile, to display: DisplaySnapshot) -> DisplayModeSpec? {
        guard let preferred = profile.mode else { return nil }
        let current = DisplayKit.currentMode(for: display.displayID)
        // Режим уже стоит нужный — трогать конфигурацию экранов незачем.
        // Плотность точек сравнивается наравне с размером: 1920x1080 бывает и
        // обычным, и удвоенным, и это разные режимы.
        if let current, current.width == preferred.width, current.height == preferred.height,
           current.refreshHz == preferred.refreshHz, current.isHiDPI == preferred.isHiDPI {
            return nil
        }
        guard let target = ModeSelector.best(for: preferred,
                                             from: DisplayKit.availableModes(for: display.displayID)) else {
            Log.state("режим \(preferred.encoded) недоступен для «\(display.name)»")
            return nil
        }
        let ok = DisplayKit.apply(target, to: display.displayID)
        Log.state("режим \(target.width)x\(target.height) @ \(target.refreshHz) Гц"
                  + (target.isHiDPI ? " (удвоенная плотность)" : "")
                  + " для «\(display.name)» -> \(ok)")
        return ok ? current : nil
    }

    private func applyTone(of profile: DisplayProfile, to display: DisplaySnapshot) {
        brightness.apply(profile.brightnessLevel,
                         whitePoint: profile.whitePoint,
                         blueReduction: profile.blueReduction,
                         to: display.displayID)
    }

    /// Переключение профиля: настройки применяются сразу, без подтверждения.
    /// Режим в профиле человек уже видел, когда его выбирал.
    func selectProfile(_ id: UUID, for display: DisplaySnapshot) {
        profiles.setActive(id, for: display.identity)
        guard let profile = profiles.active(for: display.identity) else { return }
        applyMode(of: profile, to: display)
        applyTone(of: profile, to: display)
        Log.state("профиль «\(profile.name)» для «\(display.name)»")
        refresh()
    }

    @discardableResult
    func addProfile(named name: String, basedOn source: DisplayProfile?,
                    for display: DisplaySnapshot) -> DisplayProfile {
        var profile = source ?? DisplayProfile(name: name)
        profile.id = UUID()
        profile.name = name
        let saved = profiles.add(profile, for: display.identity)
        applyMode(of: saved, to: display)
        applyTone(of: saved, to: display)
        refresh()
        return saved
    }

    func removeProfile(_ id: UUID, for display: DisplaySnapshot) {
        profiles.remove(id, for: display.identity)
        if let active = profiles.active(for: display.identity) {
            applyMode(of: active, to: display)
            applyTone(of: active, to: display)
        }
        refresh()
    }

    func renameProfile(_ id: UUID, to name: String, for display: DisplaySnapshot) {
        guard var profile = profiles.profiles(for: display.identity).first(where: { $0.id == id }) else { return }
        profile.name = name
        profiles.update(profile, for: display.identity)
        refresh()
    }

    /// Горячая клавиша: следующий профиль активного внешнего экрана по кругу.
    func cycleProfile() {
        guard let target = brightnessTarget,
              let next = profiles.next(for: target.identity) else { return }
        selectProfile(next.id, for: target)
        onProfileCycled?(target, next)
    }

    /// Показать, на что переключились: горячую клавишу нажимают вслепую.
    var onProfileCycled: ((DisplaySnapshot, DisplayProfile) -> Void)?

    // MARK: Режим экрана

    /// Применяет режим немедленно, когда пользователь выбрал его в настройках.
    ///
    /// Смена режима — то место, где приложение может незаметно оставить
    /// человека без изображения: отличить «экран есть» от «экран чёрный»
    /// программно нельзя. Поэтому после смены спрашиваем подтверждение и сами
    /// возвращаем прежний режим, если ответа нет.
    func setMode(_ mode: PreferredMode?, for display: DisplaySnapshot) {
        var profile = ensureProfile(for: display)
        let previousMode = profile.mode
        let previousSpec = DisplayKit.currentMode(for: display.displayID)
        profile.mode = mode
        profiles.update(profile, for: display.identity)
        profileAppliedTo.insert(display.identity)

        guard let mode else { refresh(); return }
        guard let target = ModeSelector.best(for: mode,
                                             from: DisplayKit.availableModes(for: display.displayID)) else {
            Log.state("режим \(mode.encoded) недоступен для «\(display.name)»")
            refresh()
            return
        }
        let ok = DisplayKit.apply(target, to: display.displayID)
        Log.state("режим \(target.width)x\(target.height) @ \(target.refreshHz) Гц"
                  + (target.isHiDPI ? " (удвоенная плотность)" : "")
                  + " для «\(display.name)» -> \(ok)")
        refresh()
        guard ok, let previousSpec, previousSpec != target else { return }

        ModeConfirmation.ask(mode: target, displayName: display.name) { [weak self] keep in
            guard let self, !keep else { return }
            Log.state("режим не подтверждён — возвращаю \(previousSpec.resolutionLabel)")
            DisplayKit.apply(previousSpec, to: display.displayID)
            if var current = self.profiles.active(for: display.identity) {
                current.mode = previousMode
                self.profiles.update(current, for: display.identity)
            }
            self.refresh()
        }
    }

    func availableModes(for display: DisplaySnapshot) -> [DisplayModeSpec] {
        DisplayKit.availableModes(for: display.displayID)
    }

    func currentMode(for display: DisplaySnapshot) -> DisplayModeSpec? {
        DisplayKit.currentMode(for: display.displayID)
    }

    // MARK: Яркость и чёткость

    /// Экран, к которому относятся ползунки: доверенный внешний, иначе просто
    /// первый внешний.
    var brightnessTarget: DisplaySnapshot? {
        let externals = state.externals
        return externals.first { trustedDevices.contains($0.identity) } ?? externals.first
    }

    /// Ползунки в строке меню относятся к активному внешнему экрану.
    func setBrightness(_ level: BrightnessLevel) {
        guard let target = brightnessTarget else { return }
        setBrightness(level, for: target)
    }

    func setWhitePoint(_ whitePoint: WhitePoint) {
        guard let target = brightnessTarget else { return }
        setWhitePoint(whitePoint, for: target)
    }

    func setBlueReduction(_ blue: BlueReduction) {
        guard let target = brightnessTarget else { return }
        setBlueReduction(blue, for: target)
    }

    func setBrightness(_ level: BrightnessLevel, for display: DisplaySnapshot) {
        var profile = ensureProfile(for: display)
        profile.brightness = level.value
        profiles.update(profile, for: display.identity)
        brightness.apply(level,
                         whitePoint: profile.whitePoint,
                         blueReduction: profile.blueReduction,
                         to: display.displayID)
        if display.identity == brightnessTarget?.identity { state.brightness = level }
        notify()
    }

    func setWhitePoint(_ whitePoint: WhitePoint, for display: DisplaySnapshot) {
        var profile = ensureProfile(for: display)
        profile.kelvin = whitePoint.kelvin
        profiles.update(profile, for: display.identity)
        applyTone(of: profile, to: display)
        if display.identity == brightnessTarget?.identity { state.whitePoint = whitePoint }
        notify()
    }

    func setBlueReduction(_ blue: BlueReduction, for display: DisplaySnapshot) {
        var profile = ensureProfile(for: display)
        profile.blue = blue.value
        profiles.update(profile, for: display.identity)
        applyTone(of: profile, to: display)
        if display.identity == brightnessTarget?.identity { state.blueReduction = blue }
        notify()
    }

    // MARK: Ручное управление

    /// Явное переключение состояния встроенного экрана тумблером.
    func setBuiltinEnabled(_ enabled: Bool) {
        clearSuppression()
        state.override = Policy.override(settingBuiltinEnabled: enabled, currentInput())
        refresh()
    }

    private func currentInput() -> PolicyInput {
        PolicyInput(displays: state.displays,
                    builtinEnabled: state.builtinEnabled,
                    trusted: trustedDevices.all,
                    override: state.override,
                    suppressed: suppressed)
    }

    /// Явное действие пользователя означает, что экран живой: подавление
    /// после сна больше не нужно.
    private func clearSuppression() {
        wakeRestoreWork?.cancel()
        suppressed.removeAll()
    }

    func toggleBuiltin() {
        clearSuppression()
        state.override = Policy.toggle(currentInput())
        refresh()
    }

    /// Заполняется подсказкой о незнакомых экранах; меню читает это поле.
    var pendingDisplays: [DisplaySnapshot] = []

    func setTrusted(_ trusted: Bool, for identity: DisplayIdentity) {
        trustedDevices.setTrusted(trusted, for: identity)
        clearSuppression()
        // Явное решение пользователя отменяет прежнее ручное переопределение.
        state.override = .none
        refresh()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
