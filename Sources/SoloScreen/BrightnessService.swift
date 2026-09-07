import Foundation
import CoreGraphics
import SoloCore

/// Программная яркость внешнего экрана через гамма-таблицу.
///
/// Аппаратный путь (DDC/CI) недоступен: у AR-очков его нет, что подтверждено
/// замером `DisplayServicesCanChangeBrightness`.
///
/// Яркость встроенного экрана не трогается никогда — иначе сломается
/// автоподстройка, которая сама корректно переживает выключение экрана.
final class BrightnessService {
    private(set) var level: BrightnessLevel = .default
    private var appliedTo: Set<CGDirectDisplayID> = []

    func apply(_ level: BrightnessLevel, to displayID: CGDirectDisplayID) {
        self.level = level
        let value = Float(level.value)
        CGSetDisplayTransferByFormula(displayID,
                                      0.0, value, 1.0,
                                      0.0, value, 1.0,
                                      0.0, value, 1.0)
        appliedTo.insert(displayID)
    }

    /// Каждое новое подключение начинается со 100%.
    func resetToFull(_ displayID: CGDirectDisplayID) {
        level = .default
        apply(.default, to: displayID)
    }

    /// Возврат системных гамма-таблиц. Обязателен при выходе, иначе экран
    /// останется затемнённым после закрытия приложения.
    func restoreAll() {
        level = .default
        appliedTo.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
