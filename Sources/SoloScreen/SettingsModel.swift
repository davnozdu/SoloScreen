import SwiftUI
import SoloCore

/// Модель окна настроек. Держит только представление состояния координатора.
final class SettingsModel: ObservableObject {
    @Published private(set) var externals: [DisplaySnapshot] = []
    @Published private(set) var statusText: String = ""
    @Published private(set) var canCheckUpdates: Bool = false
    @Published private(set) var builtinEnabled: Bool = true
    @Published private(set) var hotKeyLabel: String = KeyCombo.default.label

    let recorder = HotKeyRecorder()

    private let coordinator: Coordinator
    var onHotKeyChange: ((KeyCombo) -> Void)?

    init(coordinator: Coordinator = .shared) {
        self.coordinator = coordinator
        reload()
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func reload() {
        externals = coordinator.state.externals
        builtinEnabled = coordinator.state.builtinEnabled
        canCheckUpdates = UpdaterService.shared.canCheck
        statusText = Self.status(for: coordinator.state)
        hotKeyLabel = HotKeyManager.stored.label
        objectWillChange.send()
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

    func resolutions(for display: DisplaySnapshot) -> [(width: Int, height: Int)] {
        ModeSelector.resolutions(in: modes(for: display))
    }

    func refreshRates(for display: DisplaySnapshot, width: Int, height: Int) -> [Int] {
        ModeSelector.refreshRates(forWidth: width, height: height, in: modes(for: display))
    }

    /// Ключ выбранного разрешения: `automatic`, когда режим не закреплён.
    static let automaticResolution = "automatic"

    func resolutionKey(for display: DisplaySnapshot) -> String {
        guard let preferred = coordinator.preferredModes.mode(for: display.identity) else {
            return Self.automaticResolution
        }
        return "\(preferred.width)x\(preferred.height)"
    }

    func resolutionBinding(for display: DisplaySnapshot) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.resolutionKey(for: display) ?? Self.automaticResolution },
            set: { [weak self] key in
                guard let self else { return }
                guard key != Self.automaticResolution else {
                    self.coordinator.setPreferredMode(nil, for: display)
                    self.reload()
                    return
                }
                let parts = key.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                // Разрешение выбрано — берём для него лучшую доступную частоту.
                let best = self.refreshRates(for: display, width: parts[0], height: parts[1]).first ?? 60
                self.coordinator.setPreferredMode(
                    PreferredMode(width: parts[0], height: parts[1], refreshHz: best), for: display)
                self.reload()
            }
        )
    }

    func refreshBinding(for display: DisplaySnapshot) -> Binding<Int> {
        Binding(
            get: { [weak self] in
                guard let self else { return 60 }
                if let preferred = self.coordinator.preferredModes.mode(for: display.identity) {
                    return preferred.refreshHz
                }
                return self.coordinator.currentMode(for: display)?.refreshHz ?? 60
            },
            set: { [weak self] hz in
                guard let self,
                      let preferred = self.coordinator.preferredModes.mode(for: display.identity)
                else { return }
                self.coordinator.setPreferredMode(
                    PreferredMode(width: preferred.width, height: preferred.height, refreshHz: hz),
                    for: display)
                self.reload()
            }
        )
    }

    /// Что показывать, пока режим не закреплён.
    func currentModeLabel(for display: DisplaySnapshot) -> String {
        guard let mode = coordinator.currentMode(for: display) else { return "—" }
        return "\(mode.resolutionLabel) · \(mode.refreshLabel)"
    }

    func isModePinned(for display: DisplaySnapshot) -> Bool {
        coordinator.preferredModes.mode(for: display.identity) != nil
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
        recorder.start { [weak self] combo in
            guard let self else { return }
            HotKeyManager.stored = combo
            self.onHotKeyChange?(combo)
            self.hotKeyLabel = combo.label
            self.objectWillChange.send()
        }
    }

    func resetHotKey() {
        HotKeyManager.stored = .default
        onHotKeyChange?(.default)
        hotKeyLabel = KeyCombo.default.label
        objectWillChange.send()
    }

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
