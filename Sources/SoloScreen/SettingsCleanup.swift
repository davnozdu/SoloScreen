import Foundation

/// Уборка за настройками, которых больше нет.
///
/// Версия 0.9.0 умела переключать системное сглаживание шрифта
/// (`AppleFontSmoothing`). На AR-очках оно не дало ничего — проверено на XREAL
/// One Pro, разницы между «как в системе» и «утолщать» не видно, — и функция
/// убрана. Но значение осталось бы записанным на всю систему, а это не то, что
/// удалённая функция вправе оставлять после себя.
enum SettingsCleanup {
    private static let doneKey = "FontSmoothingCleanupDone"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        let key = "AppleFontSmoothing" as CFString
        guard CFPreferencesCopyValue(key, kCFPreferencesAnyApplication,
                                     kCFPreferencesCurrentUser,
                                     kCFPreferencesCurrentHost) != nil else { return }
        CFPreferencesSetValue(key, nil, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        Log.state("сглаживание шрифта возвращено к системному значению")
    }
}
