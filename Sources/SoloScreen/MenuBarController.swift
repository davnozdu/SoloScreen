import AppKit
import SoloCore

/// Иконка в строке меню и её меню.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: Coordinator
    private let menu = NSMenu()
    private let brightnessSlider = NSSlider()
    private let brightnessLabel = NSTextField(labelWithString: "")
    private let weightSlider = NSSlider()
    private let weightLabel = NSTextField(labelWithString: "")

    var onOpenSettings: (() -> Void)?
    /// Решение по незнакомому экрану: доверять или больше не спрашивать.
    var onDecideDisplay: ((DisplayIdentity, Bool) -> Void)?

    init(coordinator: Coordinator = .shared) {
        self.coordinator = coordinator
        super.init()
        buildMenu()
        statusItem.menu = menu
        refresh()
    }

    // MARK: Сборка

    private func buildMenu() {
        menu.delegate = self
        menu.addItem(statusHeader)
        menu.addItem(promptItem)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(brightnessHeader)
        menu.addItem(brightnessItem)
        menu.addItem(weightHeader)
        menu.addItem(weightItem)
        menu.addItem(.separator())
        menu.addItem(profileSubmenuItem)
        menu.addItem(.separator())
        menu.addItem(trustedSubmenuItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Проверить обновления…", action: #selector(checkUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти из SoloScreen", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private lazy var statusHeader: NSMenuItem = {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    /// Пункт-тумблер: галочка показывает текущее состояние, а не только
    /// предлагает действие. Так видно, включён ли режим, ещё до нажатия.
    /// Подсказка про незнакомый экран. Показывается только когда есть о чём
    /// спросить, поэтому в обычной работе меню не разрастается.
    private lazy var promptItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isHidden = true
        return item
    }()

    private lazy var toggleItem: NSMenuItem = {
        let item = NSMenuItem(title: "Только внешний экран",
                              action: #selector(toggleBuiltin), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var brightnessHeader: NSMenuItem = {
        let item = NSMenuItem(title: "Яркость внешнего экрана", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var brightnessItem: NSMenuItem = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))

        brightnessSlider.frame = NSRect(x: 20, y: 4, width: 160, height: 20)
        brightnessSlider.minValue = BrightnessLevel.minimum
        brightnessSlider.maxValue = BrightnessLevel.maximum
        brightnessSlider.doubleValue = BrightnessLevel.maximum
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = true

        brightnessLabel.frame = NSRect(x: 186, y: 5, width: 46, height: 18)
        brightnessLabel.alignment = .right
        brightnessLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        brightnessLabel.textColor = .secondaryLabelColor

        container.addSubview(brightnessSlider)
        container.addSubview(brightnessLabel)

        let item = NSMenuItem()
        item.view = container
        return item
    }()

    private lazy var weightHeader: NSMenuItem = {
        let item = NSMenuItem(title: "Толщина текста", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var weightItem: NSMenuItem = {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))

        weightSlider.frame = NSRect(x: 20, y: 4, width: 160, height: 20)
        weightSlider.minValue = -1
        weightSlider.maxValue = 1
        weightSlider.doubleValue = 0
        weightSlider.target = self
        weightSlider.action = #selector(weightChanged)
        weightSlider.isContinuous = true

        weightLabel.frame = NSRect(x: 186, y: 5, width: 46, height: 18)
        weightLabel.alignment = .right
        weightLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        weightLabel.textColor = .secondaryLabelColor

        container.addSubview(weightSlider)
        container.addSubview(weightLabel)

        let item = NSMenuItem()
        item.view = container
        return item
    }()

    /// Профили активного внешнего экрана: то же, что делает горячая клавиша,
    /// но с возможностью выбрать конкретный.
    private lazy var profileSubmenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "Профиль экрана", action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        return item
    }()

    private lazy var trustedSubmenuItem: NSMenuItem = {
        let item = NSMenuItem(title: "Гасить ноутбук для устройства", action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        return item
    }()

    // MARK: Обновление вида

    func refresh() {
        let state = coordinator.state

        statusHeader.title = statusText(for: state)
        statusItem.button?.image = icon(builtinEnabled: state.builtinEnabled)
        statusItem.button?.image?.isTemplate = true

        toggleItem.state = state.builtinEnabled ? .off : .on
        // Гасить последний экран нельзя — держим пункт недоступным, чтобы это
        // было видно до нажатия.
        toggleItem.isEnabled = !state.externals.isEmpty || !state.builtinEnabled
        applyHotKeyLabel(to: toggleItem)

        let hasTarget = coordinator.brightnessTarget != nil
        brightnessSlider.isEnabled = hasTarget
        brightnessSlider.doubleValue = state.brightness.value
        brightnessLabel.stringValue = hasTarget ? "\(state.brightness.percent)%" : "—"
        brightnessHeader.title = hasTarget
            ? "Яркость: \(coordinator.brightnessTarget?.name ?? "")"
            : "Яркость внешнего экрана"

        weightSlider.isEnabled = hasTarget
        weightSlider.doubleValue = state.weight.value
        weightLabel.stringValue = hasTarget ? weightText(state.weight) : "—"

        rebuildProfileSubmenu()
        rebuildTrustedSubmenu(state)
        rebuildPrompt()
    }

    private func rebuildPrompt() {
        guard let display = coordinator.pendingDisplays.first else {
            promptItem.isHidden = true
            promptItem.submenu = nil
            return
        }
        promptItem.isHidden = false
        promptItem.title = "Новый экран: \(display.name)"

        let submenu = NSMenu()
        let trust = NSMenuItem(title: "Гасить ноутбук для него",
                               action: #selector(acceptPrompt(_:)), keyEquivalent: "")
        trust.target = self
        trust.representedObject = display.identity
        submenu.addItem(trust)

        let dismiss = NSMenuItem(title: "Не спрашивать больше",
                                 action: #selector(dismissPrompt(_:)), keyEquivalent: "")
        dismiss.target = self
        dismiss.representedObject = display.identity
        submenu.addItem(dismiss)
        promptItem.submenu = submenu
    }

    @objc private func acceptPrompt(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? DisplayIdentity else { return }
        onDecideDisplay?(identity, true)
    }

    @objc private func dismissPrompt(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? DisplayIdentity else { return }
        onDecideDisplay?(identity, false)
    }

    /// Сочетание показывается в самом заголовке, а не через `keyEquivalent`.
    ///
    /// То же сочетание уже висит на глобальной горячей клавише Carbon, и
    /// `keyEquivalent` добавил бы второй обработчик: при активном приложении
    /// экран переключался бы дважды подряд, что со стороны выглядит как
    /// неработающая клавиша.
    private func applyHotKeyLabel(to item: NSMenuItem) {
        item.title = "Только внешний экран  (\(HotKeyManager.stored.label))"
    }

    private func statusText(for state: Coordinator.State) -> String {
        if !state.builtinEnabled { return "Встроенный экран выключен" }
        if state.externals.isEmpty { return "Только встроенный экран" }
        return "Работают оба экрана"
    }

    private func icon(builtinEnabled: Bool) -> NSImage? {
        let name = builtinEnabled ? "display.2" : "eyeglasses"
        return NSImage(systemSymbolName: name, accessibilityDescription: "SoloScreen")
    }

    private func rebuildProfileSubmenu() {
        let submenu = NSMenu()
        defer { profileSubmenuItem.submenu = submenu }

        guard let target = coordinator.brightnessTarget else {
            let empty = NSMenuItem(title: "Внешних экранов нет", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            profileSubmenuItem.title = "Профиль экрана"
            return
        }

        let profiles = coordinator.profiles.profiles(for: target.identity)
        let active = coordinator.activeProfile(for: target)
        profileSubmenuItem.title = "Профиль: \(active?.name ?? "—")"

        if profiles.isEmpty {
            let empty = NSMenuItem(title: "Профилей нет", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for profile in profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.state = profile.id == active?.id ? .on : .off
                item.representedObject = profile.id.uuidString
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        let next = NSMenuItem(title: "Следующий  (\(HotKeyManager.storedProfile.label))",
                              action: #selector(cycleProfile), keyEquivalent: "")
        next.target = self
        next.isEnabled = profiles.count > 1
        submenu.addItem(next)
    }

    private func rebuildTrustedSubmenu(_ state: Coordinator.State) {
        let submenu = NSMenu()
        if state.externals.isEmpty {
            let empty = NSMenuItem(title: "Внешних экранов нет", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for display in state.externals {
                let item = NSMenuItem(title: display.name, action: #selector(toggleTrusted(_:)), keyEquivalent: "")
                item.target = self
                item.state = coordinator.trustedDevices.contains(display.identity) ? .on : .off
                item.representedObject = display.identity
                submenu.addItem(item)
            }
        }
        trustedSubmenuItem.submenu = submenu
    }

    // MARK: Действия

    @objc private func toggleBuiltin() { coordinator.toggleBuiltin() }

    @objc private func brightnessChanged() {
        coordinator.setBrightness(BrightnessLevel(brightnessSlider.doubleValue))
    }

    /// Знак важнее числа: «+30 %» и «−30 %» — противоположные направления.
    private func weightText(_ weight: TextWeight) -> String {
        weight.value == 0 ? "0" : String(format: "%+d%%", weight.percent)
    }

    @objc private func weightChanged() {
        coordinator.setTextWeight(TextWeight(weightSlider.doubleValue))
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw),
              let target = coordinator.brightnessTarget else { return }
        coordinator.selectProfile(id, for: target)
        refresh()
    }

    @objc private func cycleProfile() {
        coordinator.cycleProfile()
        refresh()
    }

    @objc private func toggleTrusted(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? DisplayIdentity else { return }
        coordinator.setTrusted(sender.state != .on, for: identity)
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func checkUpdates() { UpdaterService.shared.checkForUpdates() }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        coordinator.refresh()
        refresh()
    }
}
