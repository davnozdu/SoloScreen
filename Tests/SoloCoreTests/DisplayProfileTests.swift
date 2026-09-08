import Foundation
import Testing
@testable import SoloCore

private let очки = DisplayIdentity(vendorID: 0x3647, modelID: 0x4100, serialNumber: 0)
private let монитор = DisplayIdentity(vendorID: 0x1111, modelID: 0x2222, serialNumber: 3)

private func свежееХранилище(_ line: Int = #line) -> DisplayProfiles {
    let suite = "профили-тест-\(line)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return DisplayProfiles(defaults: defaults)
}

@Suite("Профили устройства")
struct DisplayProfileTests {

    @Test("У нового устройства профилей нет")
    func пустоеХранилище() {
        let store = свежееХранилище()
        #expect(store.profiles(for: очки).isEmpty)
        #expect(store.active(for: очки) == nil)
    }

    @Test("Добавленный профиль становится активным и переживает перечитывание")
    func добавлениеИЧтение() {
        let suite = "профили-тест-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DisplayProfiles(defaults: defaults)

        let saved = store.add(DisplayProfile(name: "Чтение",
                                             mode: PreferredMode(width: 960, height: 540,
                                                                 refreshHz: 120, isHiDPI: true),
                                             brightness: 0.8, weight: 0.5), for: очки)
        #expect(store.active(for: очки)?.id == saved.id)

        let другой = DisplayProfiles(defaults: defaults)
        let прочитанный = другой.active(for: очки)
        #expect(прочитанный?.name == "Чтение")
        #expect(прочитанный?.mode?.isHiDPI == true)
        #expect(прочитанный?.brightness == 0.8)
        #expect(прочитанный?.weight == 0.5)
    }

    @Test("Профили разных устройств не смешиваются")
    func профилиНеСмешиваются() {
        let store = свежееХранилище()
        store.add(DisplayProfile(name: "Очки"), for: очки)
        store.add(DisplayProfile(name: "Монитор"), for: монитор)
        #expect(store.profiles(for: очки).map(\.name) == ["Очки"])
        #expect(store.profiles(for: монитор).map(\.name) == ["Монитор"])
    }

    @Test("Одинаковые имена разводятся номерами")
    func именаУникальны() {
        let store = свежееХранилище()
        store.add(DisplayProfile(name: "Чтение"), for: очки)
        store.add(DisplayProfile(name: "Чтение"), for: очки)
        store.add(DisplayProfile(name: "Чтение"), for: очки)
        #expect(store.profiles(for: очки).map(\.name) == ["Чтение", "Чтение 2", "Чтение 3"])
    }

    @Test("Пустое имя заменяется осмысленным")
    func пустоеИмя() {
        let store = свежееХранилище()
        let saved = store.add(DisplayProfile(name: "   "), for: очки)
        #expect(!saved.name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("Переключение идёт по кругу")
    func переключениеПоКругу() {
        let store = свежееХранилище()
        let a = store.add(DisplayProfile(name: "A"), for: очки)
        let b = store.add(DisplayProfile(name: "B"), for: очки)
        let c = store.add(DisplayProfile(name: "C"), for: очки)

        store.setActive(a.id, for: очки)
        #expect(store.next(for: очки)?.id == b.id)
        store.setActive(b.id, for: очки)
        #expect(store.next(for: очки)?.id == c.id)
        store.setActive(c.id, for: очки)
        #expect(store.next(for: очки)?.id == a.id)
    }

    @Test("Правка профиля сохраняется")
    func правкаПрофиля() {
        let store = свежееХранилище()
        var profile = store.add(DisplayProfile(name: "Чтение"), for: очки)
        profile.weight = 0.9
        profile.name = "Чтение днём"
        store.update(profile, for: очки)
        #expect(store.profiles(for: очки).first?.weight == 0.9)
        #expect(store.profiles(for: очки).first?.name == "Чтение днём")
    }

    @Test("Удаление активного профиля передаёт активность соседу")
    func удалениеАктивного() {
        let store = свежееХранилище()
        let a = store.add(DisplayProfile(name: "A"), for: очки)
        let b = store.add(DisplayProfile(name: "B"), for: очки)
        store.setActive(a.id, for: очки)
        store.remove(a.id, for: очки)
        #expect(store.profiles(for: очки).count == 1)
        #expect(store.active(for: очки)?.id == b.id)
    }

    @Test("Удаление последнего профиля оставляет устройство без активного")
    func удалениеПоследнего() {
        let store = свежееХранилище()
        let a = store.add(DisplayProfile(name: "A"), for: очки)
        store.remove(a.id, for: очки)
        #expect(store.profiles(for: очки).isEmpty)
        #expect(store.active(for: очки) == nil)
    }

    @Test("Переключение при единственном профиле возвращает его же")
    func единственныйПрофиль() {
        let store = свежееХранилище()
        let a = store.add(DisplayProfile(name: "A"), for: очки)
        #expect(store.next(for: очки)?.id == a.id)
    }

    @Test("Яркость и толщина профиля обрезаются по допустимому диапазону")
    func значенияОбрезаются() {
        let store = свежееХранилище()
        let saved = store.add(DisplayProfile(name: "Кривой", brightness: 5, weight: -3), for: очки)
        #expect(saved.brightnessLevel.value == BrightnessLevel.maximum)
        #expect(saved.textWeight.value == -1)
    }

    @Test("Профиль без новых полей читается, а не стирает всё хранилище")
    func чтениеСтарогоФормата() throws {
        // Профили лежат одним куском JSON: строгий разбор означал бы, что
        // добавленное поле обнуляет настройки всех устройств разом.
        let json = """
        {"очки":[{"id":"\(UUID().uuidString)","name":"Старый","brightness":0.7}]}
        """
        let decoded = try JSONDecoder().decode([String: [DisplayProfile]].self,
                                               from: Data(json.utf8))
        let profile = try #require(decoded["очки"]?.first)
        #expect(profile.name == "Старый")
        #expect(profile.brightness == 0.7)
        #expect(profile.weight == 0)
        #expect(profile.mode == nil)
    }
}
