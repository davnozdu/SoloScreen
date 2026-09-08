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
    let preferredModes = PreferredModes()
    /// Режим выставляется один раз на подключение, а не при каждом опросе.
    private var modeAppliedTo: Set<DisplayIdentity> = []
    private let brightness = BrightnessService()
    private let defaults = UserDefaults.standard
    private let lastBuiltinKey = "LastBuiltinDisplayID"

    /// Наши собственные вызовы тоже поднимают reconfiguration-события; без этого
    /// флага политика зациклилась бы на собственных изменениях.
    private var isApplying = false
    private var pendingRefresh: DispatchWorkItem?
    private var watchdog: Timer?
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

    func refresh() {
        let displays = DisplayKit.onlineDisplays()
        if let builtin = displays.first(where: { $0.isBuiltin }) {
            defaults.set(NSNumber(value: builtin.displayID), forKey: lastBuiltinKey)
        }

        let builtinEnabled = displays.contains { $0.isBuiltin }
        let input = PolicyInput(displays: displays,
                                builtinEnabled: builtinEnabled,
                                trusted: trustedDevices.all,
                                override: state.override)
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
        syncPreferredModes(for: displays)
        syncBrightness(for: displays)
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

    // MARK: Режимы экрана

    /// Выставляет выбранный пользователем режим при подключении устройства.
    ///
    /// macOS для AR-очков нередко выбирает 60 Гц, хотя устройство умеет больше,
    /// а высокие частоты прячет из «Настроек».
    private func syncPreferredModes(for displays: [DisplaySnapshot]) {
        let connected = Set(displays.filter { !$0.isBuiltin }.map(\.identity))
        modeAppliedTo.formIntersection(connected)

        for display in displays where !display.isBuiltin {
            guard !modeAppliedTo.contains(display.identity),
                  let preferred = preferredModes.mode(for: display.identity) else { continue }
            modeAppliedTo.insert(display.identity)

            let current = DisplayKit.currentMode(for: display.displayID)
            if let current, current.width == preferred.width, current.height == preferred.height,
               current.refreshHz == preferred.refreshHz {
                continue
            }
            guard let target = ModeSelector.best(for: preferred,
                                                 from: DisplayKit.availableModes(for: display.displayID)) else {
                Log.state("режим \(preferred.encoded) недоступен для «\(display.name)»")
                continue
            }
            let ok = DisplayKit.apply(target, to: display.displayID)
            Log.state("режим \(target.width)x\(target.height) @ \(target.refreshHz) Гц "
                      + "для «\(display.name)» -> \(ok)")
        }
    }

    /// Применяет режим немедленно, когда пользователь выбрал его в настройках.
    func setPreferredMode(_ mode: PreferredMode?, for display: DisplaySnapshot) {
        preferredModes.set(mode, for: display.identity)
        modeAppliedTo.remove(display.identity)
        guard let mode,
              let target = ModeSelector.best(for: mode,
                                             from: DisplayKit.availableModes(for: display.displayID)) else {
            refresh()
            return
        }
        modeAppliedTo.insert(display.identity)
        let ok = DisplayKit.apply(target, to: display.displayID)
        Log.state("режим \(target.width)x\(target.height) @ \(target.refreshHz) Гц "
                  + "для «\(display.name)» -> \(ok)")
        refresh()
    }

    func availableModes(for display: DisplaySnapshot) -> [DisplayModeSpec] {
        DisplayKit.availableModes(for: display.displayID)
    }

    func currentMode(for display: DisplaySnapshot) -> DisplayModeSpec? {
        DisplayKit.currentMode(for: display.displayID)
    }

    // MARK: Яркость

    /// Экран, к которому относится слайдер: доверенный внешний, иначе просто
    /// первый внешний.
    var brightnessTarget: DisplaySnapshot? {
        let externals = state.externals
        return externals.first { trustedDevices.contains($0.identity) } ?? externals.first
    }

    private var lastBrightnessTarget: DisplayIdentity?

    private func syncBrightness(for displays: [DisplaySnapshot]) {
        guard let target = brightnessTarget else {
            if lastBrightnessTarget != nil {
                brightness.restoreAll()
                lastBrightnessTarget = nil
                state.brightness = .default
            }
            return
        }
        // Каждое новое подключение начинается со 100%.
        if lastBrightnessTarget != target.identity {
            lastBrightnessTarget = target.identity
            brightness.resetToFull(target.displayID)
            state.brightness = .default
        }
    }

    func setBrightness(_ level: BrightnessLevel) {
        guard let target = brightnessTarget else { return }
        brightness.apply(level, to: target.displayID)
        state.brightness = level
        notify()
    }

    // MARK: Ручное управление

    /// Явное переключение состояния встроенного экрана тумблером.
    func setBuiltinEnabled(_ enabled: Bool) {
        state.override = Policy.override(settingBuiltinEnabled: enabled, currentInput())
        refresh()
    }

    private func currentInput() -> PolicyInput {
        PolicyInput(displays: state.displays,
                    builtinEnabled: state.builtinEnabled,
                    trusted: trustedDevices.all,
                    override: state.override)
    }

    func toggleBuiltin() {
        state.override = Policy.toggle(currentInput())
        refresh()
    }

    func setTrusted(_ trusted: Bool, for identity: DisplayIdentity) {
        trustedDevices.setTrusted(trusted, for: identity)
        // Явное решение пользователя отменяет прежнее ручное переопределение.
        state.override = .none
        refresh()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
