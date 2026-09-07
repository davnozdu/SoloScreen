import Testing
import Foundation
@testable import SoloCore

@Suite("Идентификация экрана")
struct DisplayIdentityTests {
    @Test("Ключ переживает кругооборот")
    func кругооборот() {
        let id = DisplayIdentity(vendorID: 0x610, modelID: 0xa051, serialNumber: 0xfd626d62)
        #expect(DisplayIdentity(key: id.key) == id)
    }

    @Test("Некорректный ключ отвергается")
    func мусор() {
        #expect(DisplayIdentity(key: "мусор") == nil)
        #expect(DisplayIdentity(key: "1-2") == nil)
    }
}

@Suite("Яркость")
struct BrightnessTests {
    @Test("По умолчанию 100%")
    func сто() { #expect(BrightnessLevel.default.percent == 100) }

    @Test("Нижняя граница не пускает экран в чёрное", arguments: [0.0, -5.0, 0.05])
    func нижняяГраница(_ raw: Double) {
        #expect(abs(BrightnessLevel(raw).value - 0.1) < 0.0001)
    }

    @Test("Верхняя граница ограничена сотней")
    func верхняяГраница() { #expect(abs(BrightnessLevel(3.0).value - 1.0) < 0.0001) }

    @Test("NaN не превращает экран в чёрный")
    func nanБезопасен() { #expect(abs(BrightnessLevel(.nan).value - 1.0) < 0.0001) }
}

@Suite("Белый список: хранение")
struct TrustedDevicesTests {
    @Test("Добавление и удаление переживают перезапуск")
    func сохранение() {
        let storage = InMemoryTrustedDeviceStorage()
        let devices = TrustedDevices(storage: storage)
        let id = DisplayIdentity(vendorID: 1, modelID: 2, serialNumber: 3)

        devices.setTrusted(true, for: id)
        #expect(devices.contains(id))
        #expect(TrustedDevices(storage: storage).contains(id))

        devices.setTrusted(false, for: id)
        #expect(!TrustedDevices(storage: storage).contains(id))
    }

    @Test("Повреждённые ключи игнорируются")
    func мусорВХранилище() {
        let storage = InMemoryTrustedDeviceStorage(keys: ["мусор", "00000001-00000002-00000003"])
        #expect(TrustedDevices(storage: storage).all.count == 1)
    }
}
