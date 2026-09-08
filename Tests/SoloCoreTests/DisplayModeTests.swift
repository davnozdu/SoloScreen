import Testing
@testable import SoloCore

/// Срез режимов XREAL One Pro, снятый с живого устройства.
private let xrealModes: [DisplayModeSpec] = [
    DisplayModeSpec(width: 1920, height: 1080, refreshHz: 120, isHiDPI: false),
    DisplayModeSpec(width: 1920, height: 1080, refreshHz: 90, isHiDPI: false),
    DisplayModeSpec(width: 1920, height: 1080, refreshHz: 60, isHiDPI: false),
    DisplayModeSpec(width: 1904, height: 1071, refreshHz: 120, isHiDPI: true),
    DisplayModeSpec(width: 1904, height: 1071, refreshHz: 120, isHiDPI: false),
    DisplayModeSpec(width: 1280, height: 720, refreshHz: 60, isHiDPI: false),
]

@Suite("Режимы экрана")
struct DisplayModeTests {

    @Test("Находит нужную частоту")
    func находитЧастоту() {
        let mode = ModeSelector.best(for: PreferredMode(width: 1920, height: 1080, refreshHz: 120),
                                     from: xrealModes)
        #expect(mode?.refreshHz == 120)
        #expect(mode?.width == 1920)
    }

    @Test("Из одинаковых выбирает вариант с большей плотностью точек")
    func предпочитаетHiDPI() {
        let mode = ModeSelector.best(for: PreferredMode(width: 1904, height: 1071, refreshHz: 120),
                                     from: xrealModes)
        #expect(mode?.isHiDPI == true)
    }

    @Test("Не подставляет похожий режим вместо запрошенного")
    func строгоеСовпадение() {
        // 144 Гц устройство не умеет — молча уронить до 120 нельзя.
        #expect(ModeSelector.best(for: PreferredMode(width: 1920, height: 1080, refreshHz: 144),
                                  from: xrealModes) == nil)
    }

    @Test("Разрешения идут от большего к меньшему без повторов")
    func списокРазрешений() {
        let list = ModeSelector.resolutions(in: xrealModes)
        #expect(list.count == 3)
        #expect(list.first?.width == 1920)
        #expect(list.last?.width == 1280)
    }

    @Test("Частоты для разрешения — от большей к меньшей")
    func списокЧастот() {
        #expect(ModeSelector.refreshRates(forWidth: 1920, height: 1080, in: xrealModes) == [120, 90, 60])
        #expect(ModeSelector.refreshRates(forWidth: 1280, height: 720, in: xrealModes) == [60])
    }

    @Test("Выбор переживает кругооборот через хранилище")
    func кругооборот() {
        let mode = PreferredMode(width: 1920, height: 1080, refreshHz: 120)
        #expect(PreferredMode(encoded: mode.encoded) == mode)
        #expect(PreferredMode(encoded: "мусор") == nil)
        #expect(PreferredMode(encoded: "1920x1080") == nil)
    }
}
