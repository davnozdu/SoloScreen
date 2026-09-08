import Testing
@testable import SoloCore

@Suite("Тональная кривая")
struct ToneCurveTests {

    @Test("В нейтральном положении и на полной яркости кривая ничего не меняет")
    func нейтральнаяКривая() {
        let t = ToneCurve.tables(brightness: .default)
        #expect(t.red.count == 256)
        for channel in [t.red, t.green, t.blue] {
            #expect(abs(channel[0] - 0) < 0.001)
            #expect(abs(channel[128] - 128.0 / 255.0) < 0.01)
            #expect(abs(channel[255] - 1) < 0.001)
        }
    }

    @Test("Яркость опускает верхнюю точку всех каналов одинаково")
    func яркостьОпускаетПотолок() {
        let t = ToneCurve.tables(brightness: BrightnessLevel(0.5))
        #expect(abs(t.red[255] - 0.5) < 0.001)
        #expect(abs(t.green[255] - 0.5) < 0.001)
        #expect(abs(t.blue[255] - 0.5) < 0.001)
    }

    @Test("Тёплая точка белого гасит синий сильнее зелёного и не трогает красный")
    func тёплаяТочкаБелого() {
        let warm = ToneCurve.tables(brightness: .default, whitePoint: WhitePoint(2700))
        #expect(abs(warm.red[255] - 1) < 0.001)
        #expect(warm.green[255] < warm.red[255])
        #expect(warm.blue[255] < warm.green[255])
    }

    @Test("Чем ниже кельвины, тем меньше синего")
    func синийУбываетСКельвинами() {
        var previous = 1.0
        for kelvin in [6500.0, 5000, 4000, 3000, 2000] {
            let blue = WhitePoint(kelvin).gains.blue
            #expect(blue <= previous + 0.001, "синий вырос на \(kelvin) K")
            previous = blue
        }
        #expect(WhitePoint(2000).gains.blue < 0.2)
    }

    @Test("Ослабление синего трогает только синий канал")
    func ослаблениеСинего() {
        let t = ToneCurve.tables(brightness: .default, blueReduction: BlueReduction(1))
        #expect(abs(t.red[255] - 1) < 0.001)
        #expect(abs(t.green[255] - 1) < 0.001)
        #expect(t.blue[255] < 0.2)
        // Совсем без синего нельзя: сине-фиолетовые элементы стали бы чёрными.
        #expect(t.blue[255] > 0.05)
    }

    @Test("Тёплая точка белого и ослабление синего складываются")
    func настройкиСкладываются() {
        let both = ToneCurve.tables(brightness: .default,
                                    whitePoint: WhitePoint(3000),
                                    blueReduction: BlueReduction(1))
        let onlyWarm = ToneCurve.tables(brightness: .default, whitePoint: WhitePoint(3000))
        #expect(both.blue[255] < onlyWarm.blue[255])
    }

    @Test("Кривые всегда неубывающие и в границах")
    func кривыеКорректны() {
        for kelvin in [6500.0, 4000, 2000] {
            for blue in [0.0, 0.5, 1.0] {
                for level in [0.1, 0.5, 1.0] {
                    let t = ToneCurve.tables(brightness: BrightnessLevel(level),
                                             whitePoint: WhitePoint(kelvin),
                                             blueReduction: BlueReduction(blue))
                    for channel in [t.red, t.green, t.blue] {
                        #expect(channel.allSatisfy { $0 >= 0 && $0 <= 1 })
                        for i in 1..<channel.count {
                            #expect(channel[i] >= channel[i - 1] - 0.0001)
                        }
                    }
                }
            }
        }
    }

    @Test("Значения за границами диапазона обрезаются")
    func значенияОбрезаются() {
        #expect(WhitePoint(99_000).kelvin == WhitePoint.neutralKelvin)
        #expect(WhitePoint(100).kelvin == WhitePoint.warmestKelvin)
        #expect(WhitePoint(.nan).kelvin == WhitePoint.neutralKelvin)
        #expect(BlueReduction(-1).value == 0)
        #expect(BlueReduction(7).value == 1)
        #expect(BlueReduction(.nan).value == 0)
    }

    @Test("Подпись точки белого округляется до сотен кельвинов")
    func подписьТочкиБелого() {
        #expect(WhitePoint(6500).label == "6500 K")
        #expect(WhitePoint(3050).label == "3100 K")
    }
}
