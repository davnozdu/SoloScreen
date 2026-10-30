import SwiftUI
import SoloCore

/// Модель окна настроек. Держит только представление состояния координатора.
final class SettingsModel: ObservableObject {
    @Published private(set) var externals: [DisplaySnapshot] = []
    @Published private(set) var statusText: String = ""
    @Published private(set) var canCheckUpdates: Bool = false
    @Published private(set) var builtinEnabled: Bool = true
    @Published private(set) var hotKeyLabel: String = KeyCombo.default.label
    @Published private(set) var profileHotKeyLabel: String = KeyCombo.defaultProfileSwitch.label

    let recorder = HotKeyRecorder()

    private let coordinator: Coordinator
    /// Возвращает true, если сочетание удалось повесить на систему.
    /// Неудачную регистрацию сохранять нельзя: клавиша молча не работает
    /// и после перезапуска, а в интерфейсе выглядит назначенной.
    var onHotKeyChange: ((KeyCombo) -> Bool)?
    var onProfileHotKeyChange: ((KeyCombo) -> Bool)?

    /// Причина, по которой последнее сочетание не назначилось.
    @Published private(set) var hotKeyError: String?

    init(coordinator: Coordinator = .shared) {
        self.coordinator = coordinator
        reload()
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func reload() {
        let state = coordinator.state
        let displays = state.externals
        if displays.map(\.identity) != externals.map(\.identity) {
            // Устройства переподключились — закешированный список режимов
            // мог устареть.
            modeCache.removeAll()
        }
        // Каждое присваивание в @Published — отдельный проход `body`. Опрос идёт
        // раз в две секунды, поэтому пишем только изменившееся.
        if externals != displays { externals = displays }
        if builtinEnabled != state.builtinEnabled { builtinEnabled = state.builtinEnabled }
        let status = Self.status(for: state)
        if statusText != status { statusText = status }
        let canCheck = UpdaterService.shared.canCheck
        if canCheckUpdates != canCheck { canCheckUpdates = canCheck }
        let hotKey = HotKeyManager.stored.label
        if hotKeyLabel != hotKey { hotKeyLabel = hotKey }
        let profileHotKey = HotKeyManager.storedProfile.label
        if profileHotKeyLabel != profileHotKey { profileHotKeyLabel = profileHotKey }
    }

    private static func status(for state: Coordinator.State) -> String {
        if !state.builtinEnabled {
            return "Встроенный экран выключен, изображение идёт на внешний."
        }
        if state.externals.isEmpty {
            return "Внешних экранов нет, работает встроенный."
        }
        return "Работают оба экрана."
    }

    // MARK: Экраны

    /// Ручной тумблер: гасит встроенный экран прямо сейчас, не дожидаясь
    /// автоматики и не требуя перетыкать кабель.
    var soloBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in !(self?.builtinEnabled ?? true) },
            set: { [weak self] solo in
                self?.coordinator.setBuiltinEnabled(!solo)
                self?.reload()
            }
        )
    }

    /// Пока внешних экранов нет, гасить встроенный нельзя.
    var canGoSolo: Bool { !externals.isEmpty }

    // MARK: Профили устройства

    /// Раскрытая карточка устройства. Хранится здесь, а не во вьюхе: список
    /// перестраивается на каждом опросе экранов, и локальное состояние
    /// схлопывалось бы само.
    @Published private var expandedDisplays: Set<DisplayIdentity> = []

    func expansionBinding(for display: DisplaySnapshot) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.expandedDisplays.contains(display.identity) ?? false },
            set: { [weak self] open in
                guard let self else { return }
                if open {
                    self.expandedDisplays.insert(display.identity)
                    // Профиль создаётся при первом раскрытии: пока карточка
                    // закрыта, настройки устройства никого не интересуют.
                    self.coordinator.ensureProfile(for: display)
                } else {
                    self.expandedDisplays.remove(display.identity)
                }
                self.objectWillChange.send()
            }
        )
    }

    func profiles(for display: DisplaySnapshot) -> [DisplayProfile] {
        coordinator.profiles.profiles(for: display.identity)
    }

    func activeProfile(for display: DisplaySnapshot) -> DisplayProfile? {
        coordinator.activeProfile(for: display)
    }

    func profileBinding(for display: DisplaySnapshot) -> Binding<UUID> {
        Binding(
            get: { [weak self] in self?.activeProfile(for: display)?.id ?? UUID() },
            set: { [weak self] id in
                self?.coordinator.selectProfile(id, for: display)
                self?.reload()
            }
        )
    }

    /// Новый профиль повторяет текущий: человек обычно хочет «то же, но с одной
    /// поправкой», а не пустой лист.
    func addProfile(for display: DisplaySnapshot) {
        let source = activeProfile(for: display)
        coordinator.addProfile(named: "Новый профиль", basedOn: source, for: display)
        reload()
    }

    func removeProfile(_ id: UUID, for display: DisplaySnapshot) {
        coordinator.removeProfile(id, for: display)
        reload()
    }

    func renameProfile(_ id: UUID, to name: String, for display: DisplaySnapshot) {
        coordinator.renameProfile(id, to: name, for: display)
        reload()
    }

    func canRemoveProfile(for display: DisplaySnapshot) -> Bool {
        profiles(for: display).count > 1
    }

    func brightnessBinding(for display: DisplaySnapshot) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.activeProfile(for: display)?.brightness ?? BrightnessLevel.maximum },
            set: { [weak self] value in
                self?.coordinator.setBrightness(BrightnessLevel(value), for: display)
                self?.objectWillChange.send()
            }
        )
    }

    func whitePointBinding(for display: DisplaySnapshot) -> Binding<Double> {
        Binding(
            get: { [weak self] in
                self?.activeProfile(for: display)?.kelvin ?? WhitePoint.neutralKelvin
            },
            set: { [weak self] value in
                self?.coordinator.setWhitePoint(WhitePoint(value), for: display)
                self?.objectWillChange.send()
            }
        )
    }

    func blueBinding(for display: DisplaySnapshot) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.activeProfile(for: display)?.blue ?? 0 },
            set: { [weak self] value in
                self?.coordinator.setBlueReduction(BlueReduction(value), for: display)
                self?.objectWillChange.send()
            }
        )
    }

    // MARK: Режим экрана

    /// Перечисление режимов заметно дороже остальных опросов (у AR-очков их
    /// сотни), поэтому список кэшируется на устройство.
    private var modeCache: [DisplayIdentity: [DisplayModeSpec]] = [:]

    func modes(for display: DisplaySnapshot) -> [DisplayModeSpec] {
        if let cached = modeCache[display.identity] { return cached }
        let modes = coordinator.availableModes(for: display)
        modeCache[display.identity] = modes
        return modes
    }

    /// Пункт списка разрешений. Отдельный тип, а не кортеж: список рисуется
    /// через `ForEach`, которому нужен устойчивый идентификатор.
    struct ResolutionOption: Identifiable, Hashable {
        let width: Int
        let height: Int
        let isHiDPI: Bool

        var id: String { SettingsModel.key(width: width, height: height, isHiDPI: isHiDPI) }
        var label: String {
            let size = "\(width) × \(height)"
            return isHiDPI ? size + " — чётко" : size
        }
    }

    func resolutionOptions(for display: DisplaySnapshot) -> [ResolutionOption] {
        ModeSelector.resolutionOptions(in: modes(for: display),
                                       keeping: activeProfile(for: display)?.mode)
            .map { ResolutionOption(width: $0.width, height: $0.height, isHiDPI: $0.isHiDPI) }
    }

    func refreshRates(for display: DisplaySnapshot, width: Int, height: Int) -> [Int] {
        ModeSelector.refreshRates(forWidth: width, height: height, in: modes(for: display))
    }

    /// Ключ выбранного разрешения: `automatic`, когда режим не закреплён.
    /// Суффикс `r` — удвоенная плотность точек.
    static let automaticResolution = "automatic"

    static func key(width: Int, height: Int, isHiDPI: Bool) -> String {
        "\(width)x\(height)" + (isHiDPI ? "r" : "")
    }

    func resolutionKey(for display: DisplaySnapshot) -> String {
        guard let mode = activeProfile(for: display)?.mode else { return Self.automaticResolution }
        return Self.key(width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI)
    }

    func resolutionBinding(for display: DisplaySnapshot) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.resolutionKey(for: display) ?? Self.automaticResolution },
            set: { [weak self] key in
                guard let self else { return }
                guard key != Self.automaticResolution, let size = Self.parse(key) else {
                    self.coordinator.setMode(nil, for: display)
                    self.reload()
                    return
                }
                // Разрешение выбрано — берём для него лучшую доступную частоту.
                let best = self.refreshRates(for: display, width: size.width, height: size.height).first ?? 60
                self.coordinator.setMode(PreferredMode(width: size.width, height: size.height,
                                                       refreshHz: best, isHiDPI: size.isHiDPI),
                                         for: display)
                self.reload()
            }
        )
    }

    func refreshBinding(for display: DisplaySnapshot) -> Binding<Int> {
        Binding(
            get: { [weak self] in
                guard let self else { return 60 }
                if let mode = self.activeProfile(for: display)?.mode { return mode.refreshHz }
                return self.coordinator.currentMode(for: display)?.refreshHz ?? 60
            },
            set: { [weak self] hz in
                guard let self, let mode = self.activeProfile(for: display)?.mode else { return }
                self.coordinator.setMode(PreferredMode(width: mode.width, height: mode.height,
                                                       refreshHz: hz, isHiDPI: mode.isHiDPI),
                                         for: display)
                self.reload()
            }
        )
    }

    static func parse(_ key: String) -> (width: Int, height: Int, isHiDPI: Bool)? {
        var raw = key
        let retina = raw.hasSuffix("r")
        if retina { raw.removeLast() }
        let parts = raw.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1], retina)
    }

    /// Что показывать, пока режим не закреплён.
    func currentModeLabel(for display: DisplaySnapshot) -> String {
        guard let mode = coordinator.currentMode(for: display) else { return "—" }
        return "\(mode.resolutionLabel) · \(mode.refreshLabel)"
            + (mode.isHiDPI ? " · удвоенная плотность" : "")
    }

    func isModePinned(for display: DisplaySnapshot) -> Bool {
        activeProfile(for: display)?.mode != nil
    }

    /// Есть ли у устройства режимы с удвоенной плотностью точек. Для AR-очков
    /// это главный рычаг читаемости, и когда система их не отдаёт, об этом
    /// честнее сказать, чем молча показать список без них.
    func hasHiDPIModes(for display: DisplaySnapshot) -> Bool {
        modes(for: display).contains { $0.isHiDPI }
    }

    func trustBinding(for display: DisplaySnapshot) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.coordinator.trustedDevices.contains(display.identity) ?? false },
            set: { [weak self] value in
                self?.coordinator.setTrusted(value, for: display.identity)
                self?.reload()
            }
        )
    }

    // MARK: Горячая клавиша

    func startRecording() {
        recorder.start { [weak self] combo in self?.assign(combo, forProfile: false) }
    }

    func resetHotKey() {
        assign(.default, forProfile: false)
    }

    /// Запись сочетания идёт по одному: пишущий рекордер общий, а вот куда
    /// сохранить результат — решает вызов.
    func startRecordingProfileHotKey() {
        recorder.start { [weak self] combo in self?.assign(combo, forProfile: true) }
    }

    func resetProfileHotKey() {
        assign(.defaultProfileSwitch, forProfile: true)
    }

    /// Назначает сочетание и сохраняет его только после успешной регистрации.
    ///
    /// Проверяются два отказа, которые раньше проходили молча: сочетание уже
    /// висит на другой команде SoloScreen и сочетание занято другим
    /// приложением (`RegisterEventHotKey` вернул ошибку).
    private func assign(_ combo: KeyCombo, forProfile: Bool) {
        let other = forProfile ? HotKeyManager.stored : HotKeyManager.storedProfile
        guard combo != other else {
            hotKeyError = "Сочетание \(combo.label) уже назначено другой команде SoloScreen."
            return
        }
        let applied = forProfile ? onProfileHotKeyChange?(combo) : onHotKeyChange?(combo)
        guard applied == true else {
            // `register` снимает прежнюю клавишу до попытки поставить новую:
            // без возврата неудачная попытка оставила бы пользователя вовсе
            // без сочетания.
            if forProfile {
                _ = onProfileHotKeyChange?(HotKeyManager.storedProfile)
            } else {
                _ = onHotKeyChange?(HotKeyManager.stored)
            }
            hotKeyError = "Сочетание \(combo.label) занято другим приложением."
            return
        }
        hotKeyError = nil
        if forProfile {
            HotKeyManager.storedProfile = combo
            profileHotKeyLabel = combo.label
        } else {
            HotKeyManager.stored = combo
            hotKeyLabel = combo.label
        }
    }

    // MARK: Поведение после пробуждения

    var restoreAfterWakeBinding: Binding<Bool> {
        Binding(
            get: { WakeSettings.restoresSoloAfterWake },
            set: { [weak self] value in
                WakeSettings.restoresSoloAfterWake = value
                self?.objectWillChange.send()
            }
        )
    }

    var wakeDelayBinding: Binding<Int> {
        Binding(
            get: { WakeSettings.restoreDelaySeconds },
            set: { [weak self] value in
                WakeSettings.restoreDelaySeconds = value
                self?.objectWillChange.send()
            }
        )
    }

    var wakeDelayRange: ClosedRange<Int> { WakeSettings.delayRange }

    var loginItemBinding: Binding<Bool> {
        Binding(
            get: { LoginItemService.isEnabled },
            set: { [weak self] value in
                LoginItemService.setEnabled(value)
                self?.objectWillChange.send()
            }
        )
    }
}
