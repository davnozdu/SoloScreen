import AppKit
import Carbon.HIToolbox

/// Глобальная горячая клавиша.
///
/// Carbon `RegisterEventHotKey` выбран намеренно вместо `CGEventTap`: он не
/// требует разрешения «Универсальный доступ», поэтому приложение работает сразу
/// после установки, без похода в настройки безопасности.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private static let signature: OSType = 0x534F4C4F // 'SOLO'

    /// По умолчанию ⌃⌥⌘D.
    struct Combo {
        var keyCode: UInt32 = UInt32(kVK_ANSI_D)
        var modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
    }

    func register(_ combo: Combo = Combo(), action: @escaping () -> Void) {
        unregister()
        self.action = action

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
        RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit { unregister() }
}
