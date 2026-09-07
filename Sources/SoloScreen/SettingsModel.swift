import SwiftUI
import SoloCore

/// Модель окна настроек. Держит только представление состояния координатора.
final class SettingsModel: ObservableObject {
    @Published private(set) var externals: [DisplaySnapshot] = []
    @Published private(set) var statusText: String = ""
    @Published private(set) var canCheckUpdates: Bool = false

    private let coordinator: Coordinator
    var onHotKeyChange: ((HotKeyChoice) -> Void)?

    init(coordinator: Coordinator = .shared) {
        self.coordinator = coordinator
        reload()
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func reload() {
        externals = coordinator.state.externals
        canCheckUpdates = UpdaterService.shared.canCheck
        statusText = Self.status(for: coordinator.state)
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

    func trustBinding(for display: DisplaySnapshot) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.coordinator.trustedDevices.contains(display.identity) ?? false },
            set: { [weak self] value in
                self?.coordinator.setTrusted(value, for: display.identity)
                self?.reload()
            }
        )
    }

    var hotKeyBinding: Binding<HotKeyChoice> {
        Binding(
            get: { HotKeyChoice.current },
            set: { [weak self] choice in
                HotKeyChoice.current = choice
                self?.onHotKeyChange?(choice)
                self?.objectWillChange.send()
            }
        )
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
