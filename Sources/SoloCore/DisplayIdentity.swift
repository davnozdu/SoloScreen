import Foundation

/// Устойчивый идентификатор экрана.
///
/// Намеренно не использует `CGDirectDisplayID`: он переназначается при каждом
/// переподключении, поэтому как ключ белого списка не годится. Вместо него —
/// поля EDID, которые у конкретного устройства постоянны.
public struct DisplayIdentity: Hashable, Codable, Sendable {
    public let vendorID: UInt32
    public let modelID: UInt32
    public let serialNumber: UInt32

    public init(vendorID: UInt32, modelID: UInt32, serialNumber: UInt32) {
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
    }

    /// Строковый ключ для хранения в UserDefaults.
    public var key: String {
        String(format: "%08x-%08x-%08x", vendorID, modelID, serialNumber)
    }

    public init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let v = UInt32(parts[0], radix: 16),
              let m = UInt32(parts[1], radix: 16),
              let s = UInt32(parts[2], radix: 16) else { return nil }
        self.init(vendorID: v, modelID: m, serialNumber: s)
    }
}

/// Снимок одного экрана на момент опроса системы.
public struct DisplaySnapshot: Hashable, Sendable {
    public let displayID: UInt32
    public let identity: DisplayIdentity
    public let name: String
    public let isBuiltin: Bool

    public init(displayID: UInt32, identity: DisplayIdentity, name: String, isBuiltin: Bool) {
        self.displayID = displayID
        self.identity = identity
        self.name = name
        self.isBuiltin = isBuiltin
    }
}
