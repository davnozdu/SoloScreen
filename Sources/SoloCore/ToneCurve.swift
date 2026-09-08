import Foundation

/// Толщина штрихов текста: сдвиг полутонов гамма-кривой.
///
/// Ноль — ничего не менять. Положительные значения поднимают полутона: серая
/// кайма сглаживания вокруг светлых букв становится ярче, и штрих читается
/// толще. Отрицательные опускают: кайма гаснет, буквы тоньше, контур жёстче.
///
/// Прежний вариант — S-образная кривая со срезом теней — на очках оказался
/// бесполезен, и это не случайность: у просвечивающей оптики засветка приходит
/// из комнаты уже после панели, а гамма-таблица правит только то, что рисует
/// компьютер. Вычесть свет комнаты она не может.
public struct TextWeight: Equatable, Sendable {
    public static let neutral = TextWeight(0)

    /// От −1 (тоньше) до +1 (толще).
    public let value: Double

    public init(_ raw: Double) {
        if raw.isNaN {
            self.value = 0
        } else {
            self.value = Swift.min(Swift.max(raw, -1), 1)
        }
    }

    /// Крайние положения: гамма 0.55 и 1.8. Дальше картинка уходит в дымку или
    /// в провал теней, а текст от этого уже не выигрывает.
    private static let span = 1.8

    public var gamma: Double { pow(TextWeight.span, -value) }

    public var percent: Int { Int((value * 100).rounded()) }
}

/// Таблица переноса для экрана: яркость и толщина текста одной кривой.
///
/// Аппаратного пути нет — у AR-очков не нашлось ни одного параметра
/// `IODisplayConnect`, — поэтому и то и другое делается гамма-таблицей.
public enum ToneCurve {

    public static func table(brightness: BrightnessLevel,
                             weight: TextWeight,
                             size: Int = 256) -> [Float] {
        guard size > 1 else { return [Float(brightness.value)] }
        let gamma = weight.gamma
        return (0..<size).map { index in
            let x = Double(index) / Double(size - 1)
            return Float(Swift.min(Swift.max(pow(x, gamma) * brightness.value, 0), 1))
        }
    }
}
