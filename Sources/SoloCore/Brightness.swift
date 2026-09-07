import Foundation

/// Уровень программной яркости внешнего экрана.
///
/// Реализуется гамма-таблицей, поэтому полный ноль недопустим — экран стал бы
/// чёрным без возможности что-либо разглядеть и вернуть.
public struct BrightnessLevel: Equatable, Sendable {
    public static let minimum: Double = 0.1
    public static let maximum: Double = 1.0
    /// Каждое подключение начинается со 100%.
    public static let `default` = BrightnessLevel(1.0)

    public let value: Double

    public init(_ raw: Double) {
        if raw.isNaN {
            self.value = BrightnessLevel.maximum
        } else {
            self.value = Swift.min(Swift.max(raw, BrightnessLevel.minimum), BrightnessLevel.maximum)
        }
    }

    public var percent: Int { Int((value * 100).rounded()) }
}
