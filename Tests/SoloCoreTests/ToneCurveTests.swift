import Testing
@testable import SoloCore

@Suite("Тональная кривая")
struct ToneCurveTests {

    @Test("В нейтральном положении и на полной яркости кривая ничего не меняет")
    func нейтральнаяКривая() {
        let table = ToneCurve.table(brightness: .default, weight: .neutral)
        #expect(table.count == 256)
        #expect(abs(table[0] - 0) < 0.001)
        #expect(abs(table[128] - 128.0 / 255.0) < 0.01)
        #expect(abs(table[255] - 1) < 0.001)
    }

    @Test("Яркость опускает верхнюю точку, не поднимая нижнюю")
    func яркостьОпускаетПотолок() {
        let table = ToneCurve.table(brightness: BrightnessLevel(0.5), weight: .neutral)
        #expect(abs(table[0] - 0) < 0.001)
        #expect(abs(table[255] - 0.5) < 0.001)
    }

    @Test("Кривая всегда неубывающая")
    func криваяНеубывающая() {
        for weight in [-1.0, -0.4, 0.0, 0.4, 1.0] {
            for level in [0.1, 0.5, 1.0] {
                let table = ToneCurve.table(brightness: BrightnessLevel(level),
                                            weight: TextWeight(weight))
                for i in 1..<table.count {
                    #expect(table[i] >= table[i - 1] - 0.0001,
                            "падение на \(i) при толщине \(weight)")
                }
            }
        }
    }

    @Test("Толще — полутона выше, тоньше — ниже")
    func направлениеТолщины() {
        let neutral = ToneCurve.table(brightness: .default, weight: .neutral)
        let bolder = ToneCurve.table(brightness: .default, weight: TextWeight(1))
        let thinner = ToneCurve.table(brightness: .default, weight: TextWeight(-1))
        #expect(bolder[128] > neutral[128])
        #expect(thinner[128] < neutral[128])
        // Крайние точки не двигаются: чёрное остаётся чёрным, белое белым.
        #expect(abs(bolder[0] - neutral[0]) < 0.001)
        #expect(abs(bolder[255] - neutral[255]) < 0.001)
    }

    @Test("Сдвиг полутонов заметен глазу, а не теряется в округлении")
    func сдвигЗаметен() {
        let neutral = ToneCurve.table(brightness: .default, weight: .neutral)
        let bolder = ToneCurve.table(brightness: .default, weight: TextWeight(1))
        // Прежняя S-образная кривая давала на середине разницу меньше 0.02 —
        // ровно поэтому её и не было видно на очках.
        #expect(bolder[128] - neutral[128] > 0.08)
    }

    @Test("Значения не выходят за границы даже на пределе настроек")
    func значенияВГраницах() {
        for weight in [-1.0, 1.0] {
            let table = ToneCurve.table(brightness: BrightnessLevel(0.1), weight: TextWeight(weight))
            #expect(table.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }

    @Test("Толщина за границами диапазона обрезается")
    func толщинаОбрезается() {
        #expect(TextWeight(-5).value == -1)
        #expect(TextWeight(5).value == 1)
        #expect(TextWeight(.nan).value == 0)
    }
}
