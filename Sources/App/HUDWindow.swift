import AppKit

@MainActor
final class HUDWindowController {
    private var panel: NSPanel?

    func show(
        success: Bool,
        title: String,
        subtitle: String? = nil,
        duration: TimeInterval = 1.35,
        completion: @escaping @MainActor () -> Void
    ) {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let symbolName = success ? "checkmark.circle.fill" : "xmark.circle.fill"
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let iconImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(symbolConfig)

        let iconView = NSImageView()
        iconView.image = iconImage
        iconView.contentTintColor = success ? .systemGreen : .systemRed
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        if let subtitle, !subtitle.isEmpty {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.maximumNumberOfLines = 2
            subtitleLabel.preferredMaxLayoutWidth = 260
            textStack.addArrangedSubview(subtitleLabel)
        }

        let mainStack = NSStackView(views: [iconView, textStack])
        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -20),
            mainStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
            mainStack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12),
        ])

        effectView.layoutSubtreeIfNeeded()
        let fittedSize = effectView.fittingSize
        let width = max(190, ceil(fittedSize.width))
        let height = max(48, ceil(fittedSize.height))

        let screen = Self.activeScreen()
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let originX = visibleFrame.midX - width / 2.0
        let originY = visibleFrame.maxY - height - 48.0
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = 0.0
        panel.contentView = effectView

        self.panel = panel
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16 + duration) { [weak self] in
            guard let panel = self?.panel else {
                completion()
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    self?.panel = nil
                    completion()
                }
            })
        }
    }

    private static func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
