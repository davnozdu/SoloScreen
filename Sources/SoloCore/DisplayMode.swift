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
public struct PreferredMode: Equatable, Sendable, Codable {
    public let width: Int
    public let height: Int
    public let refreshHz: Int
    /// Удвоенная плотность точек. Хранится вместе с размером, потому что одно
    /// и то же разрешение бывает в обоих видах, а цена у них разная: у 1920x1080
    /// с удвоением кадровый буфер становится 3840x2160.
    public let isHiDPI: Bool

    public init(width: Int, height: Int, refreshHz: Int, isHiDPI: Bool = false) {
        self.width = width
        self.height = height
        self.refreshHz = refreshHz
        self.isHiDPI = isHiDPI
    }

    /// Суффикс `r` — удвоенная плотность. Записи без него остались от прежних
    /// версий и означают обычный режим.
    public var encoded: String { "\(width)x\(height)@\(refreshHz)" + (isHiDPI ? "r" : "") }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "@")
        guard parts.count == 2 else { return nil }
        var tail = String(parts[1])
        let retina = tail.hasSuffix("r")
        if retina { tail.removeLast() }
        guard let hz = Int(tail) else { return nil }
        let size = parts[0].split(separator: "x")
        guard size.count == 2, let w = Int(size[0]), let h = Int(size[1]) else { return nil }
        self.init(width: w, height: h, refreshHz: hz, isHiDPI: retina)
    }

    // Наружу уходит одна строка: и в UserDefaults, и внутри профиля запись
    // выглядит одинаково.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let decoded = PreferredMode(encoded: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "непонятный режим: \(raw)"))
        }
        self = decoded
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoded)
    }
}

public enum ModeSelector {

    /// Подбирает режим под выбор пользователя.
    ///
    /// Совпадение строгое: подставлять «похожий» режим нельзя, иначе очки молча
    /// оказались бы не на той частоте, ради которой всё и затевалось. Плотность
    /// точек тоже берётся та, которую просили: удвоение стоит видеоядру
    /// вчетверо большего кадрового буфера, само собой его включать нельзя.
    /// Уступка одна: если удвоенного режима у устройства нет, подойдёт обычный
    /// того же размера — картинка та же, просто без сглаживания.
    public static func best(for preferred: PreferredMode,
                            from modes: [DisplayModeSpec]) -> DisplayModeSpec? {
        let matching = modes.filter {
            $0.width == preferred.width
                && $0.height == preferred.height
                && $0.refreshHz == preferred.refreshHz
        }
        return matching.first { $0.isHiDPI == preferred.isHiDPI } ?? matching.first
    }

    /// Разрешения для списка выбора — от большего к меньшему, без повторов.
    public static func resolutions(in modes: [DisplayModeSpec]) -> [(width: Int, height: Int)] {
        resolutionOptions(in: modes).map { ($0.width, $0.height) }
    }

    /// Разрешения, которые имеет смысл предлагать человеку.
    ///
    /// Телевизионные устройства (а AR-очки система числит именно телевизором)
    /// отдают лестницу размеров с шагом 16 пикселей — это компенсация
    /// недоскана. На панели очков она ничего не меняет: проверено на XREAL One
    /// Pro, картинка растягивается обратно на весь кадр. В списке от неё только
    /// двести лишних строк.
    private static let commonSizes: Set<String> = [
        "3840x2160", "3440x1440", "2560x1600", "2560x1440", "2560x1080",
        "1920x1200", "1920x1080", "1680x1050", "1600x1200", "1600x900",
        "1440x900", "1366x768", "1280x1024", "1280x800", "1280x720",
        "1152x720", "1024x768", "1024x640", "1024x576", "960x600", "960x540",
        "800x600", "640x480", "640x360",
    ]

    /// То же, но с пометкой о плотности точек. Когда разрешение есть в обоих
    /// видах, показываются оба: у удвоенного кадровый буфер вчетверо больше, и
    /// для 1920x1080 это уже 3840x2160 — выбор между чёткостью и нагрузкой на
    /// видеоядро должен оставаться за человеком.
    public static func resolutionOptions(in modes: [DisplayModeSpec],
                                         keeping pinned: PreferredMode? = nil)
        -> [(width: Int, height: Int, isHiDPI: Bool)] {
        // Родное разрешение остаётся всегда: у нестандартной панели оно может
        // не попасть в список привычных, а без него выбирать не из чего.
        let native = modes.map { ($0.width, $0.height) }.max { ($0.0, $0.1) < ($1.0, $1.1) }

        var seen: Set<String> = []
        var options: [(width: Int, height: Int, isHiDPI: Bool)] = []
        for mode in modes {
            let key = "\(mode.width)x\(mode.height)"
            let isNative = native.map { $0.0 == mode.width && $0.1 == mode.height } ?? false
            let isPinned = pinned.map { $0.width == mode.width && $0.height == mode.height } ?? false
            guard commonSizes.contains(key) || isNative || isPinned else { continue }
            guard seen.insert(key + (mode.isHiDPI ? "r" : "")).inserted else { continue }
            options.append((mode.width, mode.height, mode.isHiDPI))
        }
        // Внутри одного размера обычный вариант идёт первым: он дешевле.
        return options.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            return !$0.isHiDPI && $1.isHiDPI
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
