import Foundation

/// Режим экрана в том виде, в каком его показывают пользователю.
public struct DisplayModeSpec: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshHz: Int
    /// Режим с удвоенной плотностью точек: картинка чётче при том же
    /// логическом размере.
    public let isHiDPI: Bool

    public init(width: Int, height: Int, refreshHz: Int, isHiDPI: Bool) {
        self.width = width
        self.height = height
        self.refreshHz = refreshHz
        self.isHiDPI = isHiDPI
    }

    public var resolutionLabel: String { "\(width) × \(height)" }
    public var refreshLabel: String { "\(refreshHz) Гц" }
}

/// Что пользователь выбрал для конкретного устройства.
public struct PreferredMode: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshHz: Int

    public init(width: Int, height: Int, refreshHz: Int) {
        self.width = width
        self.height = height
        self.refreshHz = refreshHz
    }

    public var encoded: String { "\(width)x\(height)@\(refreshHz)" }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "@")
        guard parts.count == 2, let hz = Int(parts[1]) else { return nil }
        let size = parts[0].split(separator: "x")
        guard size.count == 2, let w = Int(size[0]), let h = Int(size[1]) else { return nil }
        self.init(width: w, height: h, refreshHz: hz)
    }
}

public enum ModeSelector {

    /// Подбирает режим под выбор пользователя.
    ///
    /// Совпадение строгое: подставлять «похожий» режим нельзя, иначе очки молча
    /// оказались бы не на той частоте, ради которой всё и затевалось. Из
    /// одинаковых по размеру и частоте выбирается вариант с большей плотностью
    /// точек.
    public static func best(for preferred: PreferredMode,
                            from modes: [DisplayModeSpec]) -> DisplayModeSpec? {
        let matching = modes.filter {
            $0.width == preferred.width
                && $0.height == preferred.height
                && $0.refreshHz == preferred.refreshHz
        }
        return matching.first { $0.isHiDPI } ?? matching.first
    }

    /// Разрешения для списка выбора — от большего к меньшему, без повторов.
    public static func resolutions(in modes: [DisplayModeSpec]) -> [(width: Int, height: Int)] {
        var seen = Set<String>()
        return modes
            .sorted { ($0.width, $0.height) > ($1.width, $1.height) }
            .compactMap { mode in
                let key = "\(mode.width)x\(mode.height)"
                guard seen.insert(key).inserted else { return nil }
                return (mode.width, mode.height)
            }
    }

    /// Частоты, доступные для выбранного разрешения — от большей к меньшей.
    public static func refreshRates(forWidth width: Int, height: Int,
                                    in modes: [DisplayModeSpec]) -> [Int] {
        let rates = modes
            .filter { $0.width == width && $0.height == height }
            .map(\.refreshHz)
        return Array(Set(rates)).sorted(by: >)
    }
}

/// Хранилище выбранных режимов, по одному на устройство.
public final class PreferredModes {
    private let defaults: UserDefaults
    private let key = "PreferredDisplayModes"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func mode(for identity: DisplayIdentity) -> PreferredMode? {
        guard let raw = (defaults.dictionary(forKey: key) as? [String: String])?[identity.key] else {
            return nil
        }
        return PreferredMode(encoded: raw)
    }

    public func set(_ mode: PreferredMode?, for identity: DisplayIdentity) {
        var all = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        if let mode {
            all[identity.key] = mode.encoded
        } else {
            all.removeValue(forKey: identity.key)
        }
        defaults.set(all, forKey: key)
    }
}
