import AppKit
import SwiftUI
import SoloCore

/// Захват нового сочетания в окне настроек.
///
/// Используется локальный монитор событий, а не `CGEventTap`: он ловит клавиши,
/// только пока окно приложения активно, и потому не требует разрешения
/// «Универсальный доступ». Возврат `nil` из монитора съедает событие, чтобы
/// набираемое сочетание не срабатывало по своему прямому назначению.
final class HotKeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// Что показывать в поле: либо набираемое прямо сейчас, либо сохранённое.
    @Published private(set) var draftLabel = ""
    @Published private(set) var hint: String?

    private var monitor: Any?
    private var onFinish: ((KeyCombo) -> Void)?
    /// Пока идёт запись, глобальная горячая клавиша снимается: иначе Carbon
    /// перехватил бы её раньше окна, и переназначить сочетание на само себя
    /// было бы невозможно.
    private var onSuspendHotKey: (() -> Void)?
    private var onResumeHotKey: (() -> Void)?

    func configure(suspend: @escaping () -> Void, resume: @escaping () -> Void) {
        onSuspendHotKey = suspend
        onResumeHotKey = resume
    }

    func start(onFinish: @escaping (KeyCombo) -> Void) {
        guard !isRecording else { return }
        self.onFinish = onFinish
        isRecording = true
        draftLabel = ""
        hint = "Нажмите сочетание. Esc — отмена."
        onSuspendHotKey?()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancel() {
        finishRecording()
        hint = nil
        draftLabel = ""
    }

    /// Возвращает true, если событие поглощено.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = HotKeyRecorder.modifiers(from: event.modifierFlags)

        switch event.type {
        case .flagsChanged:
            // Показываем набираемые модификаторы, пока обычная клавиша не нажата.
            draftLabel = modifiers.label
            return true

        case .keyDown:
            let code = UInt16(event.keyCode)
            if code == 53, modifiers.isEmpty {   // Esc
                cancel()
                return true
            }
            let combo = KeyCombo(keyCode: code, modifiers: modifiers)
            guard combo.isValid else {
                hint = "Нужен хотя бы один модификатор: ⌃, ⌥, ⇧ или ⌘."
                draftLabel = modifiers.label + KeyCombo.keyLabel(for: code)
                return true
            }
            draftLabel = combo.label
            hint = nil
            finishRecording()
            onFinish?(combo)
            return true

        default:
            return false
        }
    }

    private func finishRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onResumeHotKey?()
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var result: KeyCombo.Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option)  { result.insert(.option) }
        if flags.contains(.shift)   { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
