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
