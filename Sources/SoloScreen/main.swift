import AppKit

// Smoke-тест для сборочного конвейера: доходит до этой точки только если dyld
// успешно загрузил все фреймворки, включая вложенный Sparkle.
if CommandLine.arguments.contains("--selftest") {
    let sparkleLoaded = NSClassFromString("SPUStandardUpdaterController") != nil
    let displayAPI = DisplayKit.isSupported
    print("selftest: Sparkle=\(sparkleLoaded ? "ок" : "НЕ ЗАГРУЖЕН") "
          + "управление экранами=\(displayAPI ? "ок" : "НЕДОСТУПНО")")
    exit(sparkleLoaded && displayAPI ? 0 : 1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Обычное приложение, а не агент: нужна иконка в Dock рядом с иконкой в строке меню.
application.setActivationPolicy(.regular)
application.run()
