import Foundation
import Carbon.HIToolbox

/// Набор готовых сочетаний вместо полноценного рекордера: выбор из списка
/// покрывает задачу и не требует перехвата ввода.
enum HotKeyChoice: String, CaseIterable, Identifiable {
    case controlOptionCommandD
    case controlOptionCommandL
    case controlOptionCommandB
    case shiftCommandF12

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionCommandD: return "⌃⌥⌘D"
        case .controlOptionCommandL: return "⌃⌥⌘L"
        case .controlOptionCommandB: return "⌃⌥⌘B"
        case .shiftCommandF12: return "⇧⌘F12"
        }
    }

    var combo: HotKeyManager.Combo {
        switch self {
        case .controlOptionCommandD:
            return .init(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey))
        case .controlOptionCommandL:
            return .init(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey | cmdKey))
        case .controlOptionCommandB:
            return .init(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey | cmdKey))
        case .shiftCommandF12:
            return .init(keyCode: UInt32(kVK_F12), modifiers: UInt32(shiftKey | cmdKey))
        }
    }

    private static let key = "HotKeyChoice"

    static var current: HotKeyChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let choice = HotKeyChoice(rawValue: raw) else { return .controlOptionCommandD }
            return choice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
