import Foundation
import UserNotifications
import SoloCore

/// Подсказка при первом подключении незнакомого экрана.
///
/// Без неё единственный способ узнать про белый список — самому открыть
/// настройки и найти галочку. Уведомление показывается один раз на устройство;
/// если разрешение на уведомления не выдано, приложение просто работает дальше.
final class NewDisplayNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let seenKey = "SeenDisplayKeys"
    private let categoryID = "new-display"
    private let trustActionID = "trust-display"

    var onTrustRequest: ((DisplayIdentity) -> Void)?

    func start() {
        center.delegate = self
        let trust = UNNotificationAction(identifier: trustActionID,
                                         title: "Гасить ноутбук для него",
                                         options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [trust],
                                   intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                Log.state("уведомления недоступны: \(error.localizedDescription)")
            } else if !granted {
                Log.state("уведомления не разрешены")
            }
        }
    }

    /// Вызывается на каждом опросе; уведомление уходит только для устройств,
    /// которых приложение раньше не видело.
    func noticeIfNew(_ displays: [DisplaySnapshot], trusted: Set<DisplayIdentity>) {
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        var added = false

        for display in displays where !display.isBuiltin && !display.identity.isPlaceholder {
            guard !seen.contains(display.identity.key) else { continue }
            seen.insert(display.identity.key)
            added = true
            // Уже отмеченное устройство подсказки не требует.
            guard !trusted.contains(display.identity) else { continue }
            notify(about: display)
        }
        if added { defaults.set(Array(seen).sorted(), forKey: seenKey) }
    }

    private func notify(about display: DisplaySnapshot) {
        let content = UNMutableNotificationContent()
        content.title = "Подключён экран «\(display.name)»"
        content.body = "Гасить встроенный экран, когда это устройство подключено?"
        content.categoryIdentifier = categoryID
        content.userInfo = ["identity": display.identity.key]

        let request = UNNotificationRequest(identifier: "new-display-\(display.identity.key)",
                                            content: content, trigger: nil)
        center.add(request) { error in
            if let error { Log.state("не удалось показать подсказку: \(error.localizedDescription)") }
        }
    }

    // MARK: Делегат

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == trustActionID,
              let key = response.notification.request.content.userInfo["identity"] as? String,
              let identity = DisplayIdentity(key: key) else { return }
        DispatchQueue.main.async { [weak self] in self?.onTrustRequest?(identity) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
