import Testing
@testable import SoloCore

@Suite("Сочетание клавиш")
struct KeyComboTests {

    @Test("Подпись собирается в порядке macOS")
    func подпись() {
        let combo = KeyCombo(keyCode: 2, modifiers: [.command, .control, .option])
        #expect(combo.label == "⌃⌥⌘D")
    }

    @Test("Обычная клавиша идёт последней")
    func порядок() {
        #expect(KeyCombo(keyCode: 49, modifiers: [.shift, .command]).label == "⇧⌘Пробел")
    }

    @Test("По умолчанию ⌃⌥⌘D")
    func поУмолчанию() {
        #expect(KeyCombo.default.label == "⌃⌥⌘D")
        #expect(KeyCombo.default.isValid)
    }

    @Test("Сочетание без модификаторов отвергается")
    func безМодификаторов() {
        #expect(!KeyCombo(keyCode: 2, modifiers: []).isValid)
    }

    @Test("Сочетание из одних модификаторов отвергается", arguments: [UInt16(54), 55, 58, 59, 63])
    func толькоМодификаторы(_ code: UInt16) {
        #expect(!KeyCombo(keyCode: code, modifiers: [.command]).isValid)
    }

    @Test("Запись переживает кругооборот через хранилище")
    func кругооборот() {
        let combo = KeyCombo(keyCode: 111, modifiers: [.shift, .command])
        #expect(KeyCombo.decode(combo.encoded) == combo)
    }

    @Test("Повреждённая запись не подсовывает нерабочее сочетание")
    func мусор() {
        #expect(KeyCombo.decode("мусор") == nil)
        #expect(KeyCombo.decode("2") == nil)
        // Валидное по форме, но нерегистрируемое сочетание тоже отвергается.
        #expect(KeyCombo.decode("2:0") == nil)
    }

    @Test("Неизвестный код не остаётся без подписи")
    func неизвестныйКод() {
        #expect(!KeyCombo.keyLabel(for: 200).isEmpty)
    }
}
