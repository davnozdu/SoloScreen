import Foundation

/// Хранилище белого списка. Протокол выделен, чтобы логику можно было
/// тестировать без UserDefaults.
public protocol TrustedDeviceStorage: AnyObject {
    func loadKeys() -> [String]
    func saveKeys(_ keys: [String])
}

public final class InMemoryTrustedDeviceStorage: TrustedDeviceStorage {
    private var keys: [String]
    public init(keys: [String] = []) { self.keys = keys }
    public func loadKeys() -> [String] { keys }
    public func saveKeys(_ keys: [String]) { self.keys = keys }
}

public final class UserDefaultsTrustedDeviceStorage: TrustedDeviceStorage {
    private let defaults: UserDefaults
    private let key = "TrustedDisplayKeys"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func loadKeys() -> [String] { defaults.stringArray(forKey: key) ?? [] }
    public func saveKeys(_ keys: [String]) { defaults.set(keys, forKey: key) }
}

public final class TrustedDevices {
    private let storage: TrustedDeviceStorage
    private var identities: Set<DisplayIdentity>

    public init(storage: TrustedDeviceStorage) {
        self.storage = storage
        self.identities = Set(storage.loadKeys().compactMap(DisplayIdentity.init(key:)))
    }

    public var all: Set<DisplayIdentity> { identities }

    public func contains(_ identity: DisplayIdentity) -> Bool { identities.contains(identity) }

    public func setTrusted(_ trusted: Bool, for identity: DisplayIdentity) {
        if trusted { identities.insert(identity) } else { identities.remove(identity) }
        persist()
    }

    private func persist() {
        storage.saveKeys(identities.map(\.key).sorted())
    }
}
