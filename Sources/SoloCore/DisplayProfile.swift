import Foundation

/// Набор настроек экрана под одну задачу: «чтение», «кино», «работа».
///
/// Живёт отдельно для каждого устройства: у очков и у обычного монитора
/// требования к тексту разные, а подключаются они одинаково.
public struct DisplayProfile: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Режим экрана; `nil` — оставить тот, что выбрала система.
    public var mode: PreferredMode?
    public var brightness: Double
    /// Толщина текста: от −1 (тоньше) до +1 (толще).
    public var weight: Double

    public init(id: UUID = UUID(),
                name: String,
                mode: PreferredMode? = nil,
                brightness: Double = BrightnessLevel.maximum,
                weight: Double = 0) {
        self.id = id
        self.name = name
        self.mode = mode
        self.brightness = brightness
        self.weight = weight
    }

    public var brightnessLevel: BrightnessLevel { BrightnessLevel(brightness) }
    public var textWeight: TextWeight { TextWeight(weight) }

    /// Чтение прощает отсутствие полей: профили хранятся одним куском JSON, и
    /// строгий разбор означал бы, что новое поле стирает все настройки разом.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Профиль"
        mode = try container.decodeIfPresent(PreferredMode.self, forKey: .mode)
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness)
            ?? BrightnessLevel.maximum
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 0
    }
}

/// Профили всех устройств и указатель на активный.
public final class DisplayProfiles {
    private let defaults: UserDefaults
    private let profilesKey = "DisplayProfiles"
    private let activeKey = "ActiveDisplayProfiles"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Чтение

    public func profiles(for identity: DisplayIdentity) -> [DisplayProfile] {
        guard let raw = stored()[identity.key] else { return [] }
        return raw
    }

    public func active(for identity: DisplayIdentity) -> DisplayProfile? {
        let list = profiles(for: identity)
        guard !list.isEmpty else { return nil }
        guard let activeID = activeID(for: identity),
              let found = list.first(where: { $0.id == activeID }) else { return list.first }
        return found
    }

    public func activeID(for identity: DisplayIdentity) -> UUID? {
        guard let raw = (defaults.dictionary(forKey: activeKey) as? [String: String])?[identity.key] else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    /// Следующий профиль по кругу — то, что делает горячая клавиша.
    public func next(for identity: DisplayIdentity) -> DisplayProfile? {
        let list = profiles(for: identity)
        guard !list.isEmpty else { return nil }
        guard let current = active(for: identity),
              let index = list.firstIndex(where: { $0.id == current.id }) else { return list.first }
        return list[(index + 1) % list.count]
    }

    // MARK: Правка

    @discardableResult
    public func add(_ profile: DisplayProfile, for identity: DisplayIdentity) -> DisplayProfile {
        var list = profiles(for: identity)
        var saved = normalized(profile)
        saved.name = uniqueName(saved.name, in: list)
        list.append(saved)
        write(list, for: identity)
        setActive(saved.id, for: identity)
        return saved
    }

    public func update(_ profile: DisplayProfile, for identity: DisplayIdentity) {
        var list = profiles(for: identity)
        guard let index = list.firstIndex(where: { $0.id == profile.id }) else { return }
        var saved = normalized(profile)
        saved.name = uniqueName(saved.name, in: list.filter { $0.id != profile.id })
        list[index] = saved
        write(list, for: identity)
    }

    public func remove(_ id: UUID, for identity: DisplayIdentity) {
        var list = profiles(for: identity)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list.remove(at: index)
        write(list, for: identity)

        guard activeID(for: identity) == id else { return }
        // Активным становится сосед, а не пустота: иначе устройство осталось бы
        // с настройками удалённого профиля и без способа их изменить.
        setActive(list.isEmpty ? nil : list[min(index, list.count - 1)].id, for: identity)
    }

    public func setActive(_ id: UUID?, for identity: DisplayIdentity) {
        var all = (defaults.dictionary(forKey: activeKey) as? [String: String]) ?? [:]
        if let id {
            all[identity.key] = id.uuidString
        } else {
            all.removeValue(forKey: identity.key)
        }
        defaults.set(all, forKey: activeKey)
    }

    // MARK: Хранение

    private func stored() -> [String: [DisplayProfile]] {
        guard let data = defaults.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([String: [DisplayProfile]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ list: [DisplayProfile], for identity: DisplayIdentity) {
        var all = stored()
        if list.isEmpty {
            all.removeValue(forKey: identity.key)
        } else {
            all[identity.key] = list
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: profilesKey)
    }

    private func normalized(_ profile: DisplayProfile) -> DisplayProfile {
        var result = profile
        result.brightness = BrightnessLevel(profile.brightness).value
        result.weight = TextWeight(profile.weight).value
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = trimmed.isEmpty ? "Профиль" : trimmed
        return result
    }

    /// Имена в списке видит человек, поэтому повторы разводятся номером, а не
    /// отказом сохранить.
    private func uniqueName(_ name: String, in list: [DisplayProfile]) -> String {
        let taken = Set(list.map(\.name))
        guard taken.contains(name) else { return name }
        var index = 2
        while taken.contains("\(name) \(index)") { index += 1 }
        return "\(name) \(index)"
    }
}
