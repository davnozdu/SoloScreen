import Testing
@testable import SoloCore

let glasses = DisplayIdentity(vendorID: 0x0510, modelID: 0x1001, serialNumber: 0x1)
let projector = DisplayIdentity(vendorID: 0x09d1, modelID: 0x8002, serialNumber: 0x47c)
let builtinID = DisplayIdentity(vendorID: 0x0610, modelID: 0xa051, serialNumber: 0xfd626d62)
/// Заглушка, которую macOS подставляет, когда физических экранов не осталось.
let placeholder = DisplayIdentity(vendorID: 0x756E_6B6E, modelID: 0x7669_7274, serialNumber: 0)

func snapshot(_ identity: DisplayIdentity, builtin: Bool = false, id: UInt32 = 2) -> DisplaySnapshot {
    DisplaySnapshot(displayID: id, identity: identity, name: "test", isBuiltin: builtin)
}
let builtinDisplay = snapshot(builtinID, builtin: true, id: 1)

func input(_ displays: [DisplaySnapshot],
                   builtinEnabled: Bool = true,
                   trusted: Set<DisplayIdentity> = [glasses],
                   override: ManualOverride = .none) -> PolicyInput {
    PolicyInput(displays: displays, builtinEnabled: builtinEnabled, trusted: trusted, override: override)
}

@Suite("Безопасность: без экрана остаться нельзя")
struct SafetyTests {
    @Test("Встроенный включается, когда внешних нет")
    func включаетВстроенный() {
        #expect(Policy.decide(input([builtinDisplay], builtinEnabled: false)).action == .enable)
    }

    @Test("Оверрайд сбрасывается, когда внешних нет")
    func сбрасываетОверрайд() {
        let d = Policy.decide(input([builtinDisplay], builtinEnabled: false,
                                    override: .forceBuiltinOff(anchor: glasses)))
        #expect(d.action == .enable)
        #expect(d.override == .none)
    }

    @Test("forceBuiltinOff не переживает отключение последнего внешнего")
    func оверрайдНеОставляетБезЭкрана() {
        let d = Policy.decide(input([builtinDisplay], builtinEnabled: true,
                                    override: .forceBuiltinOff(anchor: glasses)))
        #expect(d.action == .leaveAsIs)
        #expect(d.override == .none)
    }

    @Test("Заглушка системы не считается внешним экраном")
    func заглушкаНеЭкран() {
        // Когда гаснут все физические экраны, macOS подставляет виртуальный
        // дисплей. Принимать его за внешний нельзя.
        let i = input([snapshot(placeholder, id: 7)], builtinEnabled: false, override: .none)
        #expect(!i.hasAnyExternal)
        #expect(Policy.decide(i).action == .enable)
    }

    @Test("Ручной режим отпускает экран, когда очки отключили физически")
    func ручнойРежимОтпускает() {
        // Ровно наблюдавшийся случай: встроенный погашен вручную, очки
        // выдернули из порта, вместо них осталась заглушка.
        let i = input([snapshot(placeholder, id: 7)], builtinEnabled: false,
                      override: .forceBuiltinOff(anchor: glasses))
        let d = Policy.decide(i)
        #expect(d.action == .enable)
        #expect(d.override == .none)
    }

    @Test("Ручной режим отпускает экран и при подмене другим внешним")
    func якорьИсчез() {
        // Очки отключили, но остался проектор: держать встроенный выключенным
        // ради экрана, которого больше нет, незачем.
        let i = input([builtinDisplay, snapshot(projector)], builtinEnabled: false,
                      override: .forceBuiltinOff(anchor: glasses))
        let d = Policy.decide(i)
        #expect(d.action == .enable)
        #expect(d.override == .none)
    }

    @Test("Пока очки на месте, ручной режим держится")
    func якорьНаМесте() {
        let i = input([builtinDisplay, snapshot(glasses)], builtinEnabled: true,
                      override: .forceBuiltinOff(anchor: glasses))
        #expect(Policy.decide(i).action == .disable)
    }
}

@Suite("Белый список")
struct TrustListPolicyTests {
    @Test("Доверенный внешний гасит встроенный")
    func гаситПриДоверенном() {
        #expect(Policy.decide(input([builtinDisplay, snapshot(glasses)])).action == .disable)
    }

    @Test("Недоверенный внешний ничего не меняет")
    func неТрогаетПриНедоверенном() {
        #expect(Policy.decide(input([builtinDisplay, snapshot(projector)])).action == .leaveAsIs)
    }

    @Test("Встроенный возвращается, если остался только недоверенный")
    func возвращаетПриНедоверенном() {
        let i = input([builtinDisplay, snapshot(projector)], builtinEnabled: false)
        #expect(Policy.decide(i).action == .enable)
    }

    @Test("Повторное решение ничего не делает")
    func идемпотентность() {
        let i = input([builtinDisplay, snapshot(glasses)], builtinEnabled: false)
        #expect(Policy.decide(i).action == .leaveAsIs)
    }
}

@Suite("Ручное управление")
struct ManualOverrideTests {
    @Test("forceBuiltinOn возвращает экран, не отключая очки")
    func возвращаетЭкран() {
        let d = Policy.decide(input([builtinDisplay, snapshot(glasses)],
                                    builtinEnabled: false, override: .forceBuiltinOn))
        #expect(d.action == .enable)
        #expect(d.override == .forceBuiltinOn)
    }

    @Test("forceBuiltinOff гасит экран при недоверенном внешнем")
    func гаситВручную() {
        let d = Policy.decide(input([builtinDisplay, snapshot(projector)],
                                    builtinEnabled: true,
                                    override: .forceBuiltinOff(anchor: projector)))
        #expect(d.action == .disable)
    }

    @Test("Хоткей гасит экран, когда есть внешний")
    func хоткейГасит() {
        #expect(Policy.toggle(input([builtinDisplay, snapshot(glasses)], builtinEnabled: true))
                == .forceBuiltinOff(anchor: glasses))
    }

    @Test("Хоткей возвращает погашенный экран")
    func хоткейВозвращает() {
        #expect(Policy.toggle(input([builtinDisplay, snapshot(glasses)], builtinEnabled: false)) == .forceBuiltinOn)
    }

    @Test("Тумблер гасит встроенный при подключённом внешнем")
    func тумблерГасит() {
        let i = input([builtinDisplay, snapshot(glasses)], builtinEnabled: true)
        #expect(Policy.override(settingBuiltinEnabled: false, i) == .forceBuiltinOff(anchor: glasses))
    }

    @Test("Тумблер возвращает встроенный")
    func тумблерВозвращает() {
        let i = input([builtinDisplay, snapshot(glasses)], builtinEnabled: false)
        #expect(Policy.override(settingBuiltinEnabled: true, i) == .forceBuiltinOn)
    }

    @Test("Тумблер не гасит последний экран")
    func тумблерБезопасен() {
        let i = input([builtinDisplay], builtinEnabled: true)
        #expect(Policy.override(settingBuiltinEnabled: false, i) == .none)
    }

    @Test("Хоткей не гасит последний экран")
    func хоткейБезопасен() {
        #expect(Policy.toggle(input([builtinDisplay], builtinEnabled: true)) == .none)
    }
}

@Suite("Поведение вокруг сна")
struct SleepPolicyTests {

    /// После пробуждения панель очков может не ожить, хотя система показывает
    /// дисплей активным. Автоматика для такого экрана подавляется, иначе
    /// пользователь остаётся без изображения вовсе.
    @Test("Подавленное устройство не гасит встроенный экран")
    func подавленноеНеГасит() {
        let i = PolicyInput(displays: [builtinDisplay, snapshot(glasses)],
                            builtinEnabled: true,
                            trusted: [glasses],
                            override: .none,
                            suppressed: [glasses])
        #expect(!i.hasTrustedExternal)
        #expect(Policy.decide(i).action == .leaveAsIs)
    }

    @Test("Без подавления то же устройство гасит встроенный")
    func безПодавленияГасит() {
        let i = PolicyInput(displays: [builtinDisplay, snapshot(glasses)],
                            builtinEnabled: true,
                            trusted: [glasses],
                            override: .none,
                            suppressed: [])
        #expect(Policy.decide(i).action == .disable)
    }

    @Test("Подавление не мешает ручному режиму")
    func ручнойРежимСильнее() {
        // Явное нажатие горячей клавиши — сигнал, что экран живой.
        let i = PolicyInput(displays: [builtinDisplay, snapshot(glasses)],
                            builtinEnabled: true,
                            trusted: [glasses],
                            override: .forceBuiltinOff(anchor: glasses),
                            suppressed: [glasses])
        #expect(Policy.decide(i).action == .disable)
    }
}
