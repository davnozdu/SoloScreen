import Foundation

/// Точка белого экрана в кельвинах.
///
/// У очков панель находится в считанных сантиметрах от глаза, и синяя
/// составляющая бьёт в упор — понижение точки белого снимает часть нагрузки.
/// От штатного Night Shift отличается тем, что действует только на выбранное
/// устройство и живёт в профиле: экран ноутбука остаётся нейтральным.
public struct WhitePoint: Equatable, Sendable {
    public static let neutralKelvin: Double = 6500
    public static let warmestKelvin: Double = 2000
    public static let neutral = WhitePoint(neutralKelvin)

    public let kelvin: Double

    public init(_ raw: Double) {
        if raw.isNaN {
            self.kelvin = WhitePoint.neutralKelvin
        } else {
            self.kelvin = Swift.min(Swift.max(raw, WhitePoint.warmestKelvin), WhitePoint.neutralKelvin)
        }
    }

    public var isNeutral: Bool { kelvin >= WhitePoint.neutralKelvin }
    public var label: String { "\(Int((kelvin / 100).rounded()) * 100) K" }

    /// Множители каналов по приближению планковской кривой — той же, на которой
    /// работают Night Shift и подобные средства. Значения нормированы так, что
    /// 6500 K не меняет ничего.
    public var gains: (red: Double, green: Double, blue: Double) {
        let raw = WhitePoint.rawGains(kelvin)
        let base = WhitePoint.rawGains(WhitePoint.neutralKelvin)
        return (raw.0 / base.0, raw.1 / base.1, raw.2 / base.2)
    }

    private static func rawGains(_ kelvin: Double) -> (Double, Double, Double) {
        let t = kelvin / 100
        let red = t <= 66 ? 255 : 329.698_727_446 * pow(t - 60, -0.133_204_759_2)
        let green = t <= 66
            ? 99.470_802_586_1 * log(t) - 161.119_568_166_1
            : 288.122_169_528_3 * pow(t - 60, -0.075_514_849_2)
        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.517_731_223_1 * log(t - 10) - 305.044_792_730_7
        }
        func clamp(_ v: Double) -> Double { Swift.min(Swift.max(v, 1), 255) }
        return (clamp(red), clamp(green), clamp(blue))
    }
}

/// Отдельное ослабление синего канала.
///
/// Не то же самое, что тёплая точка белого: та ведёт цвет по естественной
/// траектории нагрева, поднимая красный, а это просто убирает синеву, оставляя
/// остальное на месте. Проверено на XREAL One Pro: на резкость не влияет, но
/// глазам вечером заметно легче.
public struct BlueReduction: Equatable, Sendable {
    public static let none = BlueReduction(0)

    /// Даже на максимуме синий остаётся: без него сине-фиолетовые элементы
    /// интерфейса стали бы неразличимы.
    private static let deepest = 0.85

    public let value: Double

    public init(_ raw: Double) {
        if raw.isNaN {
            self.value = 0
        } else {
            self.value = Swift.min(Swift.max(raw, 0), 1)
        }
    }

    public var gain: Double { 1 - BlueReduction.deepest * value }
    public var percent: Int { Int((value * 100).rounded()) }
}

/// Таблицы переноса для экрана: яркость и цвет одной кривой на канал.
///
/// Аппаратного пути нет — у AR-очков не нашлось ни одного параметра
/// `IODisplayConnect`, — поэтому всё делается гамма-таблицей.
public enum ToneCurve {

    public static func tables(brightness: BrightnessLevel,
                              whitePoint: WhitePoint = .neutral,
                              blueReduction: BlueReduction = .none,
                              size: Int = 256) -> (red: [Float], green: [Float], blue: [Float]) {
        let gains = whitePoint.gains
        let blueGain = gains.blue * blueReduction.gain

        func channel(_ gain: Double) -> [Float] {
            guard size > 1 else { return [Float(brightness.value * gain)] }
            return (0..<size).map { index in
                let x = Double(index) / Double(size - 1)
                return Float(Swift.min(Swift.max(x * brightness.value * gain, 0), 1))
            }
        }
        return (channel(gains.red), channel(gains.green), channel(blueGain))
    }
}
