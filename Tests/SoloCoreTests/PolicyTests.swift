import Testing
@testable import SoloCore

private let glasses = DisplayIdentity(vendorID: 0x0510, modelID: 0x1001, serialNumber: 0x1)
private let projector = DisplayIdentity(vendorID: 0x09d1, modelID: 0x8002, serialNumber: 0x47c)
private let builtinID = DisplayIdentity(vendorID: 0x0610, modelID: 0xa051, serialNumber: 0xfd626d62)

private func snapshot(_ identity: DisplayIdentity, builtin: Bool = false, id: UInt32 = 2) -> DisplaySnapshot {
    DisplaySnapshot(displayID: id, identity: identity, name: "test", isBuiltin: builtin)
}
private let builtinDisplay = snapshot(builtinID, builtin: true, id: 1)

private func input(_ displays: [DisplaySnapshot],
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
        let d = Policy.decide(input([builtinDisplay], builtinEnabled: false, override: .forceBuiltinOff))
        #expect(d.action == .enable)
        #expect(d.override == .none)
    }

    @Test("forceBuiltinOff не переживает отключение последнего внешнего")
    func оверрайдНеОставляетБезЭкрана() {
        let d = Policy.decide(input([builtinDisplay], builtinEnabled: true, override: .forceBuiltinOff))
        #expect(d.action == .leaveAsIs)
        #expect(d.override == .none)
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
                                    builtinEnabled: true, override: .forceBuiltinOff))
        #expect(d.action == .disable)
    }

    @Test("Хоткей гасит экран, когда есть внешний")
    func хоткейГасит() {
        #expect(Policy.toggle(input([builtinDisplay, snapshot(glasses)], builtinEnabled: true)) == .forceBuiltinOff)
    }

    @Test("Хоткей возвращает погашенный экран")
    func хоткейВозвращает() {
        #expect(Policy.toggle(input([builtinDisplay, snapshot(glasses)], builtinEnabled: false)) == .forceBuiltinOn)
    }

    @Test("Хоткей не гасит последний экран")
    func хоткейБезопасен() {
        #expect(Policy.toggle(input([builtinDisplay], builtinEnabled: true)) == .none)
    }
}
