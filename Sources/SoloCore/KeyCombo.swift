import Foundation

/// Сочетание клавиш: модификаторы плюс одна обычная клавиша.
///
/// Модель намеренно не зависит от Carbon и AppKit, чтобы правила проверки и
/// подписи можно было тестировать без запуска приложения.
public struct KeyCombo: Equatable, Codable, Sendable {

    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option  = Modifiers(rawValue: 1 << 1)
        public static let shift   = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Порядок принят в macOS: ⌃ ⌥ ⇧ ⌘.
        public var label: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option)  { result += "⌥" }
            if contains(.shift)   { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘D
    public static let `default` = KeyCombo(keyCode: 2, modifiers: [.control, .option, .command])

    /// ⌃⌥⌘P — переключение профиля экрана по кругу.
    public static let defaultProfileSwitch = KeyCombo(keyCode: 35, modifiers: [.control, .option, .command])

    /// Обычная клавиша последней, как принято в подписях меню macOS.
    public var label: String { modifiers.label + KeyCombo.keyLabel(for: keyCode) }

    /// Carbon `RegisterEventHotKey` не принимает сочетание без модификатора и
    /// не умеет вешать действие на сам модификатор.
    public var isValid: Bool {
        !modifiers.isEmpty && !KeyCombo.isModifier(keyCode)
    }

    // MARK: Хранение

    public static func decode(_ string: String) -> KeyCombo? {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let code = UInt16(parts[0]),
              let raw = UInt32(parts[1]) else { return nil }
        let combo = KeyCombo(keyCode: code, modifiers: Modifiers(rawValue: raw))
        return combo.isValid ? combo : nil
    }

    public var encoded: String { "\(keyCode):\(modifiers.rawValue)" }

    // MARK: Клавиши

    public static func isModifier(_ code: UInt16) -> Bool {
        (54...63).contains(code)
    }

    /// Подписи виртуальных кодов macOS.
    public static func keyLabel(for code: UInt16) -> String {
        if let named = names[code] { return named }
        return "клавиша \(code)"
    }

    private static let names: [UInt16: String] = [
        // Буквы — коды соответствуют раскладке ANSI, а не текущей раскладке
        // пользователя: сочетание привязано к физической клавише.
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
        40: "K", 45: "N", 46: "M",

        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",

        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";",
        42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",

        36: "Return", 48: "Tab", 49: "Пробел", 51: "Delete", 53: "Esc",
        76: "Enter", 117: "Fwd Delete", 115: "Home", 119: "End",
        116: "Page Up", 121: "Page Down",

        123: "←", 124: "→", 125: "↓", 126: "↑",

        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",

        54: "⌘", 55: "⌘", 56: "⇧", 60: "⇧", 58: "⌥", 61: "⌥",
        59: "⌃", 62: "⌃", 63: "Fn", 57: "Caps Lock",
    ]
}
