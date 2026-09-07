import Foundation
import CoreGraphics
import AppKit
import SoloCore

/// Единственное место в проекте, знающее про приватные системные символы.
///
/// Механизм подтверждён на живом железе (M2 Pro, macOS 26.6.2): работает без
/// прав root и без отключения SIP.
enum DisplayKit {

    private typealias ConfigureEnabledFn =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, ObjCBool) -> CGError

    /// `SLSConfigureDisplayEnabled` — основной путь, `CGSConfigureDisplayEnabled`
    /// — запасной: имена и расположение символов между версиями macOS менялись.
    private static let configureEnabled: ConfigureEnabledFn? = {
        let candidates = [
            ("SLSConfigureDisplayEnabled", "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"),
            ("CGSConfigureDisplayEnabled", "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"),
        ]
        for (symbol, path) in candidates {
            guard let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, symbol) else { continue }
            return unsafeBitCast(pointer, to: ConfigureEnabledFn.self)
        }
        return nil
    }()

    static var isSupported: Bool { configureEnabled != nil }

    // MARK: Опрос

    static func onlineDisplays() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        let names = screenNames()
        return ids.map { id in
            DisplaySnapshot(
                displayID: id,
                identity: DisplayIdentity(vendorID: CGDisplayVendorNumber(id),
                                          modelID: CGDisplayModelNumber(id),
                                          serialNumber: CGDisplaySerialNumber(id)),
                name: names[id] ?? (CGDisplayIsBuiltin(id) != 0 ? "Встроенный экран" : "Внешний экран"),
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var result: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            result[number.uint32Value] = screen.localizedName
        }
        return result
    }

    static func builtinDisplay() -> DisplaySnapshot? {
        onlineDisplays().first { $0.isBuiltin }
    }

    /// Проверка без обращения к AppKit: используется на аварийном пути, который
    /// исполняется вне главного потока, где `NSScreen` трогать нельзя.
    static func builtinIsOnline() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.contains { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Выключенный экран пропадает из списка online, поэтому его отсутствие там
    /// и означает выключенное состояние.
    static func isEnabled(_ displayID: CGDirectDisplayID) -> Bool {
        onlineDisplays().contains { $0.displayID == displayID }
    }

    // MARK: Управление

    @discardableResult
    static func setEnabled(_ displayID: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        guard let configure = configureEnabled else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        let configureResult = configure(config, displayID, ObjCBool(enabled))
        guard configureResult == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        // Намеренно .forSession, а не .permanently: изменение не переживает
        // перезагрузку, поэтому даже полный отказ приложения лечится ребутом,
        // а не походом за внешним монитором.
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}
