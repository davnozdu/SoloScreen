import Foundation
import os

/// Диагностика решений о состоянии экранов.
///
/// Пишется в `~/Library/Logs/SoloScreen.log`: приложение управляет тем, видит
/// ли пользователь изображение вообще, поэтому разбор нештатной ситуации не
/// должен зависеть от доступности unified log.
enum Log {
    private static let logger = Logger(subsystem: "com.davnozdu.soloscreen", category: "state")
    private static let queue = DispatchQueue(label: "com.davnozdu.soloscreen.log")

    private static let fileURL: URL? = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Logs", isDirectory: true)
        guard let logs else { return nil }
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("SoloScreen.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Журнал ведётся годами и без присмотра, поэтому его размер ограничен.
    private static let sizeLimit = 512 * 1024

    static func state(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        guard let fileURL else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded(fileURL)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Половина журнала отбрасывается разом: посимвольное усечение на каждой
    /// записи стоило бы дороже самой записи.
    private static func rotateIfNeeded(_ url: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > sizeLimit else { return }
        guard let contents = try? Data(contentsOf: url) else { return }
        let tail = contents.suffix(sizeLimit / 2)
        // Обрезаем до начала ближайшей строки, чтобы журнал не начинался с
        // половины записи.
        let newline = UInt8(ascii: "\n")
        let trimmed = tail.firstIndex(of: newline).map { tail[tail.index(after: $0)...] } ?? tail
        try? Data(trimmed).write(to: url)
    }

    /// Диагностика при завершении пишется синхронно: процесс может исчезнуть
    /// раньше, чем асинхронная запись доберётся до диска.
    static func flush() {
        queue.sync {}
    }
}
