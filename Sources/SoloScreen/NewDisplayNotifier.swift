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

    /// Устройства, о которых пользователь ещё не принял решение.
    ///
    /// Меню опирается именно на этот список, а не на уведомления: без платного
    /// Developer ID macOS отказывает приложению в правах на уведомления
    /// («Notifications are not allowed for this application»), и подсказка,
    /// построенная только на них, до пользователя не дошла бы.
    private(set) var pending: [DisplaySnapshot] = []
    /// Устройства, о которых уведомление уже показывали.
    private var notified: Set<String> = []

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

    /// Вызывается на каждом опросе.
    func noticeIfNew(_ displays: [DisplaySnapshot], trusted: Set<DisplayIdentity>) {
        let decided = Set(defaults.stringArray(forKey: seenKey) ?? [])

        pending = displays.filter { display in
            !display.isBuiltin
                && !display.identity.isPlaceholder
                && !decided.contains(display.identity.key)
                && !trusted.contains(display.identity)
        }

        for display in pending where !notified.contains(display.identity.key) {
            notified.insert(display.identity.key)
            notify(about: display)
        }
    }

    /// Решение принято — больше про это устройство не спрашиваем.
    func markDecided(_ identity: DisplayIdentity) {
        var decided = Set(defaults.stringArray(forKey: seenKey) ?? [])
        decided.insert(identity.key)
        defaults.set(Array(decided).sorted(), forKey: seenKey)
        pending.removeAll { $0.identity == identity }
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
