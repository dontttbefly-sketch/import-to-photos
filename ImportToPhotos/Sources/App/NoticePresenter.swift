import AppKit

enum NoticePresenter {
    private static var transientNoticePanel: NSPanel?

    static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    static func showTimedNotice(
        _ notice: NoticeKind,
        terminateAfterClose: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        showTimedNotice(
            message: notice.message,
            symbolName: notice.symbolName,
            tintColor: notice.tintColor,
            terminateAfterClose: terminateAfterClose,
            completion: completion
        )
    }

    private static func showTimedNotice(
        message: String,
        symbolName: String,
        tintColor: NSColor,
        terminateAfterClose: Bool,
        completion: (() -> Void)?
    ) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
            let size = NSSize(width: min(max(textWidth + 74, 156), 220), height: 44)
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let finalFrame = NSRect(
                x: screenFrame.maxX - size.width - 28,
                y: screenFrame.maxY - size.height - 34,
                width: size.width,
                height: size.height
            )
            let initialFrame = finalFrame.offsetBy(dx: 0, dy: 8)
            let exitFrame = finalFrame.offsetBy(dx: 0, dy: 6)

            let panel = NSPanel(
                contentRect: initialFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.level = .statusBar
            panel.alphaValue = 0
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

            let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            container.material = .hudWindow
            container.blendingMode = .behindWindow
            container.state = .active
            container.wantsLayer = true
            container.layer?.cornerRadius = 14
            container.layer?.masksToBounds = true
            container.layer?.borderWidth = 0.5
            container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

            let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let icon = NSImageView(frame: NSRect(x: 16, y: 13, width: 18, height: 18))
            let symbol = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: message
            )?.withSymbolConfiguration(symbolConfiguration)
            symbol?.isTemplate = true
            icon.image = symbol
            icon.contentTintColor = tintColor
            icon.imageScaling = .scaleProportionallyDown
            container.addSubview(icon)

            let label = NSTextField(labelWithString: message)
            label.alignment = .center
            label.font = font
            label.textColor = .labelColor
            label.frame = NSRect(x: 42, y: 12, width: size.width - 58, height: 20)
            label.lineBreakMode = .byTruncatingTail
            container.addSubview(label)

            panel.contentView = container
            transientNoticePanel = panel
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(finalFrame, display: true)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0
                    panel.animator().setFrame(exitFrame, display: true)
                } completionHandler: {
                    transientNoticePanel?.close()
                    transientNoticePanel = nil
                    completion?()
                    if terminateAfterClose {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
