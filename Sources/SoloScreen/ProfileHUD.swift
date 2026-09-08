import AppKit
import SoloCore

/// Короткая подсказка о том, какой профиль включился.
///
/// Горячую клавишу нажимают вслепую, а системные уведомления в самостоятельно
/// подписанной сборке недоступны: `UNUserNotificationCenter` отвечает
/// «Notifications are not allowed for this application». Поэтому подсказка
/// рисуется своим окном — и на том экране, которого касается смена профиля.
final class ProfileHUD {
    static let shared = ProfileHUD()

    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func show(profile: DisplayProfile, on display: DisplaySnapshot) {
        let text = "Профиль: \(profile.name)"
        let subtitle = display.name

        let panel = window ?? makeWindow()
        window = panel
        guard let content = panel.contentView as? HUDView else { return }
        content.update(title: text, subtitle: subtitle)

        let size = content.fittingSize
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                == display.displayID
        } ?? NSScreen.main
        if let frame = screen?.frame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                                  y: frame.minY + frame.height * 0.12,
                                  width: size.width, height: size.height),
                           display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.window?.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.window?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makeWindow() -> NSWindow {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.contentView = HUDView()
        return panel
    }
}

private final class HUDView: NSView {
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor

        title.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(title: String, subtitle: String) {
        self.title.stringValue = title
        self.subtitle.stringValue = subtitle
        needsLayout = true
    }
}
