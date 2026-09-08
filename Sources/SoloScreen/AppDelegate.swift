import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var menuBar: MenuBarController?
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?
    private let hotKey = HotKeyManager()
    private let profileHotKey = HotKeyManager(id: 2)
    private let notifier = NewDisplayNotifier()
    private var signalSources: [DispatchSourceSignal] = []
    private let signalQueue = DispatchQueue(label: "com.davnozdu.soloscreen.signals")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard DisplayKit.isSupported else {
            presentUnsupportedAlert()
            NSApp.terminate(nil)
            return
        }

        let coordinator = Coordinator.shared
        let menuBar = MenuBarController()
        menuBar.onOpenSettings = { [weak self] in self?.showSettings() }
        self.menuBar = menuBar

        coordinator.onChange = { [weak self] in
            self?.menuBar?.refresh()
            self?.settingsModel?.reload()
        }

        SettingsCleanup.run()
        hotKey.register(HotKeyManager.stored) { coordinator.toggleBuiltin() }
        profileHotKey.register(HotKeyManager.storedProfile) { coordinator.cycleProfile() }
        coordinator.onProfileCycled = { display, profile in
            ProfileHUD.shared.show(profile: profile, on: display)
        }

        notifier.onTrustRequest = { [weak self] identity in
            self?.notifier.markDecided(identity)
            Coordinator.shared.setTrusted(true, for: identity)
        }
        notifier.start()
        coordinator.onDisplaysScanned = { [weak self] displays, trusted in
            guard let self else { return }
            self.notifier.noticeIfNew(displays, trusted: trusted)
            Coordinator.shared.pendingDisplays = self.notifier.pending
        }
        menuBar.onDecideDisplay = { [weak self] identity, trust in
            self?.notifier.markDecided(identity)
            if trust { Coordinator.shared.setTrusted(true, for: identity) }
            self?.menuBar?.refresh()
        }
        installSignalHandlers()
        _ = UpdaterService.shared

        Log.state("приложение запущено, обработчики сигналов установлены")
        coordinator.start()
    }

    /// Рубеж 2: возврат экрана при завершении приложения, в том числе по сигналу.
    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        profileHotKey.unregister()
        Coordinator.shared.restoreBeforeExit()
    }

    /// Клик по иконке в Dock открывает настройки.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Настройки

    private func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            settingsModel?.reload()
            return
        }

        let model = SettingsModel()
        model.onProfileHotKeyChange = { [weak self] combo in
            self?.profileHotKey.register(combo) { Coordinator.shared.cycleProfile() }
        }
        model.onHotKeyChange = { [weak self] combo in
            self?.hotKey.register(combo) { Coordinator.shared.toggleBuiltin() }
        }
        // На время записи глобальная клавиша снимается, иначе Carbon перехватил
        // бы её раньше окна и переназначить сочетание на само себя не вышло бы.
        model.recorder.configure(
            suspend: { [weak self] in
                self?.hotKey.unregister()
                self?.profileHotKey.unregister()
            },
            resume: { [weak self] in
                self?.hotKey.register(HotKeyManager.stored) { Coordinator.shared.toggleBuiltin() }
                self?.profileHotKey.register(HotKeyManager.storedProfile) { Coordinator.shared.cycleProfile() }
            }
        )
        settingsModel = model

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SoloScreen"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Пока идёт запись сочетания, глобальная клавиша снята. Без отмены записи
    /// закрытое окно оставило бы её снятой до перезапуска приложения.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        settingsModel?.recorder.cancel()
    }

    // MARK: Сигналы

    /// SIGTERM и SIGINT приходят при логауте и при остановке из терминала:
    /// экран надо вернуть до выхода.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            // Отдельная очередь, а не главная: под управлением NSApplication
            // главная очередь не отдаёт события источникам сигналов, и
            // восстановление экрана не срабатывало.
            let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
            source.setEventHandler {
                Log.state("получен сигнал \(sig)")
                Coordinator.shared.restoreBeforeExit()
                Log.flush()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func presentUnsupportedAlert() {
        let alert = NSAlert()
        alert.messageText = "SoloScreen не может управлять экранами"
        alert.informativeText = """
        Системная функция управления дисплеями недоступна в этой версии macOS. \
        Приложение работает на Apple Silicon начиная с macOS 14.
        """
        alert.alertStyle = .critical
        alert.runModal()
    }
}
