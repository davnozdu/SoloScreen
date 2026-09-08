import Foundation
import CoreGraphics
import SoloCore

/// Яркость и толщина текста для внешнего экрана — одной таблицей переноса.
///
/// Аппаратного пути нет: у AR-очков нет ни DDC/CI, ни параметров
/// `IODisplayConnect` (проверено на XREAL One Pro — список параметров пуст).
/// Поэтому и яркость, и растяжение контраста делаются гамма-таблицей.
///
/// Яркость встроенного экрана не трогается никогда — иначе сломается
/// автоподстройка, которая сама корректно переживает выключение экрана.
final class BrightnessService {
    private(set) var level: BrightnessLevel = .default
    private(set) var weight: TextWeight = .neutral
    private var appliedTo: Set<CGDirectDisplayID> = []

    func apply(_ level: BrightnessLevel, weight: TextWeight = .neutral, to displayID: CGDirectDisplayID) {
        self.level = level
        self.weight = weight
        var table = ToneCurve.table(brightness: level, weight: weight)
        CGSetDisplayTransferByTable(displayID, UInt32(table.count), &table, &table, &table)
        appliedTo.insert(displayID)
    }

    /// Возврат системных гамма-таблиц. Обязателен при выходе, иначе экран
    /// останется затемнённым после закрытия приложения.
    func restoreAll() {
        level = .default
        weight = .neutral
        appliedTo.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
