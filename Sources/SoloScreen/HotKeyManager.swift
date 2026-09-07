import AppKit
import Carbon.HIToolbox
import SoloCore

/// Глобальная горячая клавиша.
///
/// Carbon `RegisterEventHotKey` выбран намеренно вместо `CGEventTap`: он не
/// требует разрешения «Универсальный доступ», поэтому приложение работает сразу
/// после установки. Плата за это — нельзя повесить действие на голый
/// модификатор, что и отражено в `KeyCombo.isValid`.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private(set) var current: KeyCombo?

    private static let signature: OSType = 0x534F4C4F // 'SOLO'

    /// Хранилище выбранного пользователем сочетания.
    static var stored: KeyCombo {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "HotKeyCombo"),
                  let combo = KeyCombo.decode(raw) else { return .default }
            return combo
        }
        set { UserDefaults.standard.set(newValue.encoded, forKey: "HotKeyCombo") }
    }

    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        unregister()
        guard combo.isValid else { return false }
        self.action = action
        self.current = combo

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == HotKeyManager.signature else { return noErr }
            DispatchQueue.main.async { manager.action?() }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(combo.keyCode),
                                         HotKeyManager.carbonModifiers(combo.modifiers),
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            Log.state("не удалось зарегистрировать сочетание \(combo.label): код \(status)")
            unregister()
            return false
        }
        Log.state("горячая клавиша: \(combo.label)")
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        current = nil
    }

    private static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var result: Int = 0
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option)  { result |= optionKey }
        if modifiers.contains(.shift)   { result |= shiftKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    deinit { unregister() }
}
