import Foundation
import Sparkle

/// Автообновление через Sparkle.
///
/// Релизы подписываются постоянным EdDSA-ключом, публичная половина которого
/// лежит в `Info.plist` (`SUPublicEDKey`), а appcast публикуется в GitHub
/// Releases.
final class UpdaterService {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
