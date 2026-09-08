import Foundation
import CoreGraphics
import SoloCore

/// Яркость и цвет внешнего экрана — одной таблицей переноса.
///
/// Аппаратного пути нет: у AR-очков нет ни DDC/CI, ни параметров
/// `IODisplayConnect` (проверено на XREAL One Pro — список параметров пуст).
/// Поэтому и яркость, и растяжение контраста делаются гамма-таблицей.
///
/// Яркость встроенного экрана не трогается никогда — иначе сломается
/// автоподстройка, которая сама корректно переживает выключение экрана.
final class BrightnessService {
    private(set) var level: BrightnessLevel = .default
    private(set) var whitePoint: WhitePoint = .neutral
    private(set) var blueReduction: BlueReduction = .none
    private var appliedTo: Set<CGDirectDisplayID> = []

    func apply(_ level: BrightnessLevel,
               whitePoint: WhitePoint = .neutral,
               blueReduction: BlueReduction = .none,
               to displayID: CGDirectDisplayID) {
        self.level = level
        self.whitePoint = whitePoint
        self.blueReduction = blueReduction
        var tables = ToneCurve.tables(brightness: level,
                                      whitePoint: whitePoint,
                                      blueReduction: blueReduction)
        CGSetDisplayTransferByTable(displayID, UInt32(tables.red.count),
                                    &tables.red, &tables.green, &tables.blue)
        appliedTo.insert(displayID)
    }

    /// Возврат системных гамма-таблиц. Обязателен при выходе, иначе экран
    /// останется затемнённым после закрытия приложения.
    func restoreAll() {
        level = .default
        whitePoint = .neutral
        blueReduction = .none
        appliedTo.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
