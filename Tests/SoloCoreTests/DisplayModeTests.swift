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
    DisplayModeSpec(width: 1280, height: 720, refreshHz: 120, isHiDPI: true),
    DisplayModeSpec(width: 960, height: 540, refreshHz: 120, isHiDPI: true),
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

    @Test("Без просьбы об удвоенной плотности берётся обычный режим")
    func обычныйПоУмолчанию() {
        let mode = ModeSelector.best(for: PreferredMode(width: 1904, height: 1071, refreshHz: 120),
                                     from: xrealModes)
        #expect(mode?.isHiDPI == false)
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
        // 1904x1071 отсеивается как телевизионный недоскан. Остаются
        // 1920x1080, 1280x720 в двух видах и 960x540.
        #expect(list.count == 4)
        #expect(list.first?.width == 1920)
        #expect(list.last?.width == 960)
    }

    @Test("Частоты для разрешения — от большей к меньшей")
    func списокЧастот() {
        #expect(ModeSelector.refreshRates(forWidth: 1920, height: 1080, in: xrealModes) == [120, 90, 60])
        #expect(ModeSelector.refreshRates(forWidth: 1280, height: 720, in: xrealModes) == [120, 60])
    }

    @Test("Выбор переживает кругооборот через хранилище")
    func кругооборот() {
        let mode = PreferredMode(width: 1920, height: 1080, refreshHz: 120)
        #expect(PreferredMode(encoded: mode.encoded) == mode)
        #expect(PreferredMode(encoded: "мусор") == nil)
        #expect(PreferredMode(encoded: "1920x1080") == nil)
    }

    @Test("Плотность точек хранится вместе с выбором")
    func плотностьВХранилище() {
        let retina = PreferredMode(width: 960, height: 540, refreshHz: 120, isHiDPI: true)
        #expect(PreferredMode(encoded: retina.encoded) == retina)
        #expect(retina.encoded != PreferredMode(width: 960, height: 540, refreshHz: 120).encoded)
    }

    @Test("Старые записи без плотности читаются как обычный режим")
    func староеХранилищеЧитается() {
        #expect(PreferredMode(encoded: "1920x1080@120") ==
                PreferredMode(width: 1920, height: 1080, refreshHz: 120, isHiDPI: false))
    }

    @Test("Обычный режим не подменяется удвоенным без просьбы")
    func обычныйНеПодменяется() {
        // 1920x1080 существует и как обычный, и как удвоенный: молчаливый
        // переход на удвоенный означал бы кадровый буфер 3840x2160 и лишнюю
        // работу для видеоядра.
        let modes = xrealModes + [DisplayModeSpec(width: 1920, height: 1080, refreshHz: 120, isHiDPI: true)]
        let mode = ModeSelector.best(for: PreferredMode(width: 1920, height: 1080, refreshHz: 120),
                                     from: modes)
        #expect(mode?.isHiDPI == false)
    }

    @Test("Удвоенный режим выбирается, когда его и просили")
    func удвоенныйПоПросьбе() {
        let mode = ModeSelector.best(for: PreferredMode(width: 960, height: 540,
                                                        refreshHz: 120, isHiDPI: true),
                                     from: xrealModes)
        #expect(mode?.isHiDPI == true)
        #expect(mode?.width == 960)
    }

    @Test("Если удвоенного режима нет, берётся обычный того же размера")
    func запасныйВариант() {
        let mode = ModeSelector.best(for: PreferredMode(width: 1920, height: 1080,
                                                        refreshHz: 120, isHiDPI: true),
                                     from: xrealModes)
        #expect(mode?.isHiDPI == false)
    }

    @Test("Лишние телевизионные размеры в список не попадают")
    func списокБезЛишнего() {
        // У XREAL One Pro система отдаёт лестницу режимов с шагом 16 пикселей
        // (1904x1071, 1888x1062 и так далее) — это недоскан, который на панели
        // ничего не меняет. Показывать человеку двести таких строк незачем.
        let list = ModeSelector.resolutionOptions(in: xrealModes)
        #expect(!list.contains { $0.width == 1904 })
        #expect(list.contains { $0.width == 1920 })
        #expect(list.contains { $0.width == 1280 })
        #expect(list.contains { $0.width == 960 })
    }

    @Test("Родное разрешение остаётся, даже если оно нестандартное")
    func родноеРазрешениеОстаётся() {
        let странный = [DisplayModeSpec(width: 1777, height: 1000, refreshHz: 60, isHiDPI: false)]
        let list = ModeSelector.resolutionOptions(in: странный)
        #expect(list.count == 1)
        #expect(list.first?.width == 1777)
    }

    @Test("Уже закреплённый режим не пропадает из списка")
    func закреплённыйОстаётся() {
        let pinned = PreferredMode(width: 1904, height: 1071, refreshHz: 120)
        let list = ModeSelector.resolutionOptions(in: xrealModes, keeping: pinned)
        #expect(list.contains { $0.width == 1904 })
    }

    @Test("Разрешения помечены удвоенной плотностью")
    func разрешенияСПлотностью() {
        let list = ModeSelector.resolutionOptions(in: xrealModes)
        let retina = list.first { $0.width == 960 }
        #expect(retina?.isHiDPI == true)
        let обычное = list.first { $0.width == 1920 }
        #expect(обычное?.isHiDPI == false)
        // 1280x720 есть в обоих видах — показываем оба, обычный первым.
        let семьсотДвадцать = list.filter { $0.width == 1280 }
        #expect(семьсотДвадцать.map(\.isHiDPI) == [false, true])
    }
}
