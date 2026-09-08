import AppKit
import SoloCore

/// Подтверждение смены режима экрана с автоматическим откатом.
///
/// Отличить «экран показывает картинку» от «экран чёрный» программно нельзя:
/// система в обоих случаях считает дисплей рабочим и отдаёт его режим. Поэтому
/// последнее слово за человеком, а молчание считается отказом.
enum ModeConfirmation {
    static let timeout: TimeInterval = 15

    /// Вызывает `completion(true)`, если человек подтвердил режим, и
    /// `completion(false)`, если отказался или не ответил.
    static func ask(mode: DisplayModeSpec, displayName: String,
                    completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Оставить режим \(mode.resolutionLabel)?"
            alert.informativeText = "Экран «\(displayName)» переключён на \(mode.resolutionLabel) · "
                + mode.refreshLabel
                + (mode.isHiDPI ? " с удвоенной плотностью точек" : "")
                + ".\n\nЕсли изображения нет, ничего не нажимайте: через \(Int(timeout)) с "
                + "вернётся прежний режим."
            alert.addButton(withTitle: "Оставить")
            alert.addButton(withTitle: "Вернуть")

            // Таймер вешается на common-режимы: модальное окно крутит свой цикл,
            // и обычный scheduledTimer в нём не сработал бы.
            let timer = Timer(timeInterval: timeout, repeats: false) { _ in
                NSApp.abortModal()
            }
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .modalPanel)

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            timer.invalidate()
            completion(response == .alertFirstButtonReturn)
        }
    }
}
