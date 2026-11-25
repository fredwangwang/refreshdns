import AppKit

private final class OptionsPanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

@MainActor
final class OptionsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var wakeCheckbox: NSButton?
    private var hudCheckbox: NSButton?
    private var flushButton: NSButton?
    private var uninstallButton: NSButton?
    private var doneButton: NSButton?
    private var isUpdatingToggle = false
    private var closedProgrammatically = false

    var onToggleWakeRefresh: ((Bool, @escaping @MainActor (Bool) -> Void) -> Void)?
    var onToggleWakeHUD: ((Bool) -> Void)?
    var onFlushNow: (() -> Void)?
    var onUninstall: (() -> Void)?
    var onClose: (() -> Void)?

    func show(helperStatus: HelperStatus, wakeEnabled: Bool, showHUDOnWake: Bool) {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // Header
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
        ])

        let titleLabel = NSTextField(labelWithString: "RefreshDNS")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor

        let statusField = NSTextField(labelWithString: Self.statusSubtitle(version: appVersion, status: helperStatus))
        statusField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        statusField.textColor = .secondaryLabelColor
        self.statusLabel = statusField

        let titleStack = NSStackView(views: [titleLabel, statusField])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let headerStack = NSStackView(views: [iconView, titleStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let topSeparator = makeSeparator()

        // Wake options
        let wakeButton = NSButton(
            checkboxWithTitle: L10n.optionsWakeToggleTitle,
            target: self,
            action: #selector(handleWakeToggle(_:))
        )
        wakeButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        wakeButton.state = wakeEnabled ? .on : .off
        self.wakeCheckbox = wakeButton

        let wakeDescLabel = NSTextField(wrappingLabelWithString: L10n.optionsWakeToggleDescription)
        wakeDescLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        wakeDescLabel.textColor = .secondaryLabelColor
        wakeDescLabel.preferredMaxLayoutWidth = 376

        let wakeDescContainer = NSView()
        wakeDescContainer.translatesAutoresizingMaskIntoConstraints = false
        wakeDescLabel.translatesAutoresizingMaskIntoConstraints = false
        wakeDescContainer.addSubview(wakeDescLabel)
        NSLayoutConstraint.activate([
            wakeDescLabel.leadingAnchor.constraint(equalTo: wakeDescContainer.leadingAnchor, constant: 20),
            wakeDescLabel.trailingAnchor.constraint(equalTo: wakeDescContainer.trailingAnchor),
            wakeDescLabel.topAnchor.constraint(equalTo: wakeDescContainer.topAnchor),
            wakeDescLabel.bottomAnchor.constraint(equalTo: wakeDescContainer.bottomAnchor),
        ])

        let hudButton = NSButton(
            checkboxWithTitle: L10n.optionsWakeHUDTitle,
            target: self,
            action: #selector(handleHUDToggle(_:))
        )
        hudButton.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        hudButton.state = showHUDOnWake ? .on : .off
        hudButton.isEnabled = wakeEnabled
        self.hudCheckbox = hudButton

        let hudContainer = NSView()
        hudContainer.translatesAutoresizingMaskIntoConstraints = false
        hudButton.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.addSubview(hudButton)
        NSLayoutConstraint.activate([
            hudButton.leadingAnchor.constraint(equalTo: hudContainer.leadingAnchor, constant: 20),
            hudButton.trailingAnchor.constraint(lessThanOrEqualTo: hudContainer.trailingAnchor),
            hudButton.topAnchor.constraint(equalTo: hudContainer.topAnchor, constant: 4),
            hudButton.bottomAnchor.constraint(equalTo: hudContainer.bottomAnchor),
        ])

        let optionsStack = NSStackView(views: [wakeButton, wakeDescContainer, hudContainer])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 6
        optionsStack.translatesAutoresizingMaskIntoConstraints = false

        let bottomSeparator = makeSeparator()

        // Footer buttons
        let uninstallBtn = NSButton(
            title: L10n.optionsUninstallButton,
            target: self,
            action: #selector(handleUninstall(_:))
        )
        uninstallBtn.bezelStyle = .rounded
        uninstallBtn.hasDestructiveAction = true
        self.uninstallButton = uninstallBtn

        let flushBtn = NSButton(
            title: L10n.optionsFlushNowButton,
            target: self,
            action: #selector(handleFlushNow(_:))
        )
        flushBtn.bezelStyle = .rounded
        self.flushButton = flushBtn

        let doneBtn = NSButton(
            title: L10n.optionsDoneButton,
            target: self,
            action: #selector(handleDone(_:))
        )
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        self.doneButton = doneBtn

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footerStack = NSStackView(views: [uninstallBtn, spacer, flushBtn, doneBtn])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 8
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [
            headerStack,
            topSeparator,
            optionsStack,
            bottomSeparator,
            footerStack,
        ])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            topSeparator.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            optionsStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            wakeDescContainer.widthAnchor.constraint(equalTo: optionsStack.widthAnchor),
            hudContainer.widthAnchor.constraint(equalTo: optionsStack.widthAnchor),
            bottomSeparator.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            footerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
        ])

        contentView.layoutSubtreeIfNeeded()
        let width: CGFloat = 440
        let fittingHeight = max(210, ceil(contentView.fittingSize.height))

        let win = OptionsPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: fittingHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.optionsWindowTitle
        win.isReleasedWhenClosed = false
        win.contentView = contentView
        win.delegate = self

        // Ensure fixed width & exact fitted height
        contentView.setFrameSize(NSSize(width: width, height: fittingHeight))
        contentView.layoutSubtreeIfNeeded()
        let finalHeight = ceil(contentView.fittingSize.height)
        win.setContentSize(NSSize(width: width, height: finalHeight))

        positionOnActiveScreen(win)
        self.window = win
        self.closedProgrammatically = false

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func updateHelperStatus(_ status: HelperStatus) {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
        statusLabel?.stringValue = Self.statusSubtitle(version: appVersion, status: status)
    }

    func closeProgrammatically() {
        closedProgrammatically = true
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard !closedProgrammatically else { return }
        window = nil
        onClose?()
    }

    // MARK: - Actions

    @objc private func handleWakeToggle(_ sender: NSButton) {
        guard !isUpdatingToggle else { return }
        let desired = (sender.state == .on)
        isUpdatingToggle = true
        wakeCheckbox?.isEnabled = false
        hudCheckbox?.isEnabled = false

        onToggleWakeRefresh?(desired) { [weak self] actualEnabled in
            guard let self else { return }
            self.isUpdatingToggle = false
            self.wakeCheckbox?.isEnabled = true
            self.wakeCheckbox?.state = actualEnabled ? .on : .off
            self.hudCheckbox?.isEnabled = actualEnabled
        }
    }

    @objc private func handleHUDToggle(_ sender: NSButton) {
        onToggleWakeHUD?(sender.state == .on)
    }

    @objc private func handleFlushNow(_ sender: NSButton) {
        closeProgrammatically()
        onFlushNow?()
    }

    @objc private func handleUninstall(_ sender: NSButton) {
        onUninstall?()
    }

    @objc private func handleDone(_ sender: NSButton) {
        window?.close()
    }

    // MARK: - Helpers

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func positionOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let size = window.frame.size
        let originX = visibleFrame.midX - size.width / 2.0
        let originY = visibleFrame.midY - size.height / 2.0 + 40.0
        window.setFrameOrigin(NSPoint(x: round(originX), y: round(originY)))
    }

    private static func statusSubtitle(version: String, status: HelperStatus) -> String {
        switch status {
        case .ready:
            return L10n.optionsStatusReady(version: version)
        case .needsInstall:
            return L10n.optionsStatusNotInstalled(version: version)
        case .needsUpdate:
            return L10n.optionsStatusNeedsUpdate(version: version)
        }
    }
}
