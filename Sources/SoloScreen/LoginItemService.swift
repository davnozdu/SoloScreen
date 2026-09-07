import Foundation
import ServiceManagement

/// Автозапуск через современный `SMAppService`; устаревшие LaunchAgent-плисты
/// не используются.
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("SoloScreen: не удалось изменить автозапуск: \(error.localizedDescription)")
            return false
        }
    }
}
