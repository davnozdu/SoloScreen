import Foundation

/// Что делать со встроенным экраном после пробуждения.
///
/// Наблюдавшийся случай: Mac уснул с погашенным встроенным экраном, а панель
/// AR-очков после пробуждения не ожила. Система при этом показывала дисплей
/// активным и отдавала его режим, поэтому отличить «экран есть» от «экран
/// чёрный» программно нельзя — защита возможна только через поведение.
enum WakeSettings {
    private static let restoreKey = "RestoreSoloAfterWake"
    private static let delayKey = "WakeRestoreDelaySeconds"

    /// По умолчанию встроенный экран остаётся включённым: без изображения
    /// пользователь не остаётся ни при каком стечении обстоятельств.
    static var restoresSoloAfterWake: Bool {
        get { UserDefaults.standard.bool(forKey: restoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: restoreKey) }
    }

    static let defaultDelay = 5
    static let delayRange = 1...60

    static var restoreDelaySeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: delayKey)
            guard delayRange.contains(stored) else { return defaultDelay }
            return stored
        }
        set {
            UserDefaults.standard.set(min(max(newValue, delayRange.lowerBound),
                                          delayRange.upperBound), forKey: delayKey)
        }
    }
}
