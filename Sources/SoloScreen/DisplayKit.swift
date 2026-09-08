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
    private typealias ModeCountFn =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias ModeDescriptionFn =
        @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Int32
    private typealias ConfigureModeFn =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> Int32

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

    /// Список режимов, который система отдаёт только внутренним клиентам.
    ///
    /// У AR-очков публичный `CGDisplayCopyAllDisplayModes` не показывает ни
    /// одного режима с удвоенной плотностью точек: macOS числит их телевизором.
    /// В приватном списке они есть — на XREAL One Pro это 92 режима из 423,
    /// включая 960x540 и 1280x720 с кадровым буфером вдвое больше.
    private static let modeCount: ModeCountFn? = privateSymbol("CGSGetNumberOfDisplayModes")
    private static let modeDescription: ModeDescriptionFn? = privateSymbol("CGSGetDisplayModeDescriptionOfLength")
    private static let configureMode: ConfigureModeFn? = privateSymbol("CGSConfigureDisplayMode")

    private static func privateSymbol<T>(_ name: String) -> T? {
        let paths = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, name) else { continue }
            return unsafeBitCast(pointer, to: T.self)
        }
        return nil
    }

    /// Доступны ли режимы с удвоенной плотностью точек.
    static var supportsHiddenModes: Bool { modeCount != nil && modeDescription != nil && configureMode != nil }

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

    // MARK: Режимы

    static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayModeSpec] {
        var seen = Set<DisplayModeSpec>()
        for mode in publicModes(for: displayID) where mode.refreshRate > 0 {
            seen.insert(spec(from: mode))
        }
        for hidden in hiddenModes(for: displayID) {
            seen.insert(hidden.spec)
        }
        return Array(seen)
    }

    private static func publicModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        // Просим и режимы, скрытые от «Настроек»: у AR-очков высокие частоты
        // попадают именно туда.
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: kCFBooleanTrue!] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
    }

    // MARK: Скрытые режимы

    /// Одна запись приватного списка: номер режима и то, что он означает.
    private struct HiddenMode {
        let number: Int32
        let spec: DisplayModeSpec
    }

    /// Раскладка структуры снята с живой системы (M2 Pro, macOS 26.6.2).
    /// Размер и смещения между версиями macOS менялись, поэтому весь разбор
    /// проверяется на правдоподобие, а результат — на присутствие текущего
    /// режима. Не сошлось — приватный список отбрасывается целиком, и остаётся
    /// публичный: хуже, чем сейчас, не станет.
    private enum ModeLayout {
        static let length: Int32 = 0xD4
        static let number = 0x00
        static let width = 0x08
        static let height = 0x0C
        static let refresh = 0x24     // UInt16
        static let pixelWidth = 0xC8
        static let pixelHeight = 0xCC
    }

    private static func hiddenModes(for displayID: CGDirectDisplayID) -> [HiddenMode] {
        guard let count = modeCount, let describe = modeDescription, configureMode != nil else { return [] }

        var total: Int32 = 0
        guard count(displayID, &total) == 0, total > 0, total < 10_000 else { return [] }

        var parsed: [HiddenMode] = []
        for index in 0..<total {
            var buffer = [UInt8](repeating: 0, count: Int(ModeLayout.length))
            guard describe(displayID, index, &buffer, ModeLayout.length) == 0 else { continue }
            func read32(_ offset: Int) -> UInt32 {
                buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            }
            func read16(_ offset: Int) -> UInt16 {
                buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            }
            let width = Int(read32(ModeLayout.width))
            let height = Int(read32(ModeLayout.height))
            let pixelWidth = Int(read32(ModeLayout.pixelWidth))
            let pixelHeight = Int(read32(ModeLayout.pixelHeight))
            let refresh = Int(read16(ModeLayout.refresh))

            guard (320...8192).contains(width), (200...8192).contains(height),
                  (20...480).contains(refresh),
                  pixelWidth == width || pixelWidth == width * 2,
                  pixelHeight == height || pixelHeight == height * 2 else { continue }

            parsed.append(HiddenMode(number: Int32(read32(ModeLayout.number)),
                                     spec: DisplayModeSpec(width: width, height: height,
                                                           refreshHz: refresh,
                                                           isHiDPI: pixelWidth > width)))
        }

        // Проверка разбора: то, что включено прямо сейчас, обязано найтись.
        guard let current = currentMode(for: displayID),
              parsed.contains(where: { $0.spec == current }) else {
            Log.state("приватный список режимов не сошёлся с текущим режимом — игнорирую")
            return []
        }
        return parsed
    }

    static func currentMode(for displayID: CGDirectDisplayID) -> DisplayModeSpec? {
        CGDisplayCopyDisplayMode(displayID).map(spec(from:))
    }

    private static func spec(from mode: CGDisplayMode) -> DisplayModeSpec {
        DisplayModeSpec(width: mode.width,
                        height: mode.height,
                        refreshHz: Int(mode.refreshRate.rounded()),
                        isHiDPI: mode.pixelWidth > mode.width)
    }

    /// Публичный путь предпочтительнее: он документирован и переживает
    /// обновления системы. Приватный нужен только для режимов, которых в
    /// публичном списке нет, — то есть для удвоенной плотности точек.
    @discardableResult
    static func apply(_ target: DisplayModeSpec, to displayID: CGDirectDisplayID) -> Bool {
        if let mode = publicModes(for: displayID).first(where: { spec(from: $0) == target }) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success else { return false }
            guard CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil) == .success else {
                CGCancelDisplayConfiguration(config)
                return false
            }
            return CGCompleteDisplayConfiguration(config, .forSession) == .success
        }

        guard let configure = configureMode,
              let hidden = hiddenModes(for: displayID).first(where: { $0.spec == target }) else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        guard configure(config, displayID, hidden.number) == 0 else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
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
