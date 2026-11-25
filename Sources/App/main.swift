import AppKit
import Foundation

private enum CLIHandler {
    static func handleIfNeeded() -> Never? {
        let args = Set(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            printUsage()
            exit(0)
        }

        if args.contains("--wake-status") {
            let prefEnabled = RefreshDNSPreferences.isWakeRefreshEnabled
            let loaded = WakeAgentManager.shared.isAgentLoaded
            let hudEnabled = RefreshDNSPreferences.showHUDOnWake
            print("Auto-refresh on wake: \(prefEnabled ? "enabled" : "disabled") (agent \(loaded ? "loaded" : "not loaded"))")
            print("Show HUD on wake: \(hudEnabled ? "enabled" : "disabled")")
            exit(0)
        }

        if args.contains("--wake-on") {
            switch WakeAgentManager.shared.setWakeRefreshEnabled(true) {
            case .success:
                print("Auto-refresh on wake enabled.")
                if !FileManager.default.fileExists(atPath: RefreshDNSConstants.installedHelperPath) {
                    fputs("Note: System helper is not installed yet. Launch RefreshDNS.app once to install it.\n", stderr)
                }
                exit(0)
            case .failure(let error):
                fputs("Failed to enable auto-refresh on wake: \(error.localizedMessage)\n", stderr)
                exit(1)
            }
        }

        if args.contains("--wake-off") {
            _ = WakeAgentManager.shared.setWakeRefreshEnabled(false)
            print("Auto-refresh on wake disabled.")
            exit(0)
        }

        if args.contains("--wake-hud-on") {
            RefreshDNSPreferences.showHUDOnWake = true
            print("Wake HUD notification enabled.")
            exit(0)
        }

        if args.contains("--wake-hud-off") {
            RefreshDNSPreferences.showHUDOnWake = false
            print("Wake HUD notification disabled.")
            exit(0)
        }

        return nil
    }

    private static func printUsage() {
        let text = """
        RefreshDNS - One-click macOS DNS cache flush utility

        Usage: RefreshDNS [option]

        Options:
          (no arguments)   Flush DNS cache immediately and show HUD
          --settings       Open the options window (same as holding Option while launching)
          --options        Alias for --settings
          --wake-on        Enable automatic DNS refresh on wake from sleep
          --wake-off       Disable automatic DNS refresh on wake from sleep
          --wake-hud-on    Show HUD notification on wake auto-refresh (default)
          --wake-hud-off   Hide HUD notification on wake auto-refresh (silent mode)
          --wake-status    Print current wake auto-refresh status
          --uninstall      Uninstall system helper, wake agent, and RefreshDNS.app
          -h, --help       Show this help message
        """
        print(text)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hud = HUDWindowController()
    private let optionsWindow = OptionsWindowController()
    private var currentHelperStatus: HelperStatus = .needsInstall

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = Set(CommandLine.arguments.dropFirst())

        if args.contains("--wake-flush") {
            performWakeTriggeredFlush()
            return
        }

        if args.contains("--uninstall") {
            promptUninstall(terminateOnCancel: true)
            return
        }

        let shouldOpenOptions = args.contains("--settings")
            || args.contains("--options")
            || NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)

        if shouldOpenOptions {
            openOptionsWindow()
            return
        }

        runFlushOrInstallFlow()
    }

    // MARK: - Flows

    private func runFlushOrInstallFlow() {
        HelperClient.shared.checkHelperStatus { status in
            Task { @MainActor in
                self.currentHelperStatus = status
                switch status {
                case .ready:
                    self.performFlush(isWakeAuto: false)
                case .needsInstall:
                    self.promptInstallHelper(
                        isUpdate: false,
                        installedVersion: nil,
                        showWakeOption: true,
                        terminateOnCancel: true
                    ) { installed in
                        if installed {
                            self.performFlush(isWakeAuto: false)
                        }
                    }
                case .needsUpdate(let oldVersion):
                    self.promptInstallHelper(
                        isUpdate: true,
                        installedVersion: oldVersion,
                        showWakeOption: false,
                        terminateOnCancel: true
                    ) { installed in
                        if installed {
                            self.performFlush(isWakeAuto: false)
                        }
                    }
                }
            }
        }
    }

    private func performWakeTriggeredFlush() {
        HelperClient.shared.checkHelperStatus { status in
            Task { @MainActor in
                guard case .ready = status else {
                    NSApp.terminate(nil)
                    return
                }
                self.performFlush(isWakeAuto: true)
            }
        }
    }

    private func openOptionsWindow() {
        HelperClient.shared.checkHelperStatus { status in
            DispatchQueue.global(qos: .userInitiated).async {
                WakeAgentManager.shared.syncInstalledPathIfNeeded()
                let wakeActive = WakeAgentManager.shared.isWakeRefreshActive
                let showHUD = RefreshDNSPreferences.showHUDOnWake

                Task { @MainActor in
                    self.currentHelperStatus = status
                    self.configureOptionsCallbacks()
                    self.optionsWindow.show(
                        helperStatus: status,
                        wakeEnabled: wakeActive,
                        showHUDOnWake: showHUD
                    )
                }
            }
        }
    }

    private func configureOptionsCallbacks() {
        optionsWindow.onToggleWakeRefresh = { [weak self] desired, completion in
            guard let self else {
                completion(false)
                return
            }

            if !desired {
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = WakeAgentManager.shared.setWakeRefreshEnabled(false)
                    Task { @MainActor in
                        completion(false)
                    }
                }
                return
            }

            let enableAgent: @MainActor () -> Void = {
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = WakeAgentManager.shared.setWakeRefreshEnabled(true)
                    Task { @MainActor in
                        switch result {
                        case .success:
                            completion(true)
                        case .failure(let error):
                            self.showErrorAlert(
                                title: L10n.wakeFailedTitle,
                                message: error.localizedMessage,
                                terminateAfter: false
                            )
                            completion(false)
                        }
                    }
                }
            }

            switch self.currentHelperStatus {
            case .ready:
                enableAgent()
            case .needsInstall:
                self.promptInstallHelper(
                    isUpdate: false,
                    installedVersion: nil,
                    showWakeOption: false,
                    terminateOnCancel: false
                ) { installed in
                    guard installed else {
                        completion(false)
                        return
                    }
                    self.currentHelperStatus = .ready
                    self.optionsWindow.updateHelperStatus(.ready)
                    enableAgent()
                }
            case .needsUpdate(let oldVersion):
                self.promptInstallHelper(
                    isUpdate: true,
                    installedVersion: oldVersion,
                    showWakeOption: false,
                    terminateOnCancel: false
                ) { installed in
                    guard installed else {
                        completion(false)
                        return
                    }
                    self.currentHelperStatus = .ready
                    self.optionsWindow.updateHelperStatus(.ready)
                    enableAgent()
                }
            }
        }

        optionsWindow.onToggleWakeHUD = { enabled in
            RefreshDNSPreferences.showHUDOnWake = enabled
        }

        optionsWindow.onFlushNow = { [weak self] in
            self?.runFlushOrInstallFlow()
        }

        optionsWindow.onUninstall = { [weak self] in
            self?.promptUninstall(terminateOnCancel: false)
        }

        optionsWindow.onClose = {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Uninstall

    private func promptUninstall(terminateOnCancel: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.uninstallAlertTitle
        alert.informativeText = L10n.uninstallAlertMessage
        let confirmButton = alert.addButton(withTitle: L10n.uninstallAlertConfirm)
        confirmButton.hasDestructiveAction = true
        alert.addButton(withTitle: L10n.cancel)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            if terminateOnCancel {
                NSApp.terminate(nil)
            }
            return
        }

        HelperClient.shared.uninstallHelper { result in
            Task { @MainActor in
                switch result {
                case .success:
                    self.optionsWindow.closeProgrammatically()
                    DispatchQueue.global(qos: .userInitiated).async {
                        WakeAgentManager.shared.uninstallWakeAgent()
                        Task { @MainActor in
                            self.trashAppBundleAndFinish()
                        }
                    }
                case .cancelled:
                    if terminateOnCancel {
                        NSApp.terminate(nil)
                    }
                case .failure(let message):
                    self.showErrorAlert(
                        title: L10n.uninstallFailedTitle,
                        message: message,
                        terminateAfter: terminateOnCancel
                    )
                }
            }
        }
    }

    private func trashAppBundleAndFinish() {
        let appURL = Bundle.main.bundleURL
        if appURL.pathExtension == "app" {
            do {
                try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
            } catch {
                showErrorAlert(
                    title: L10n.uninstallFailedTitle,
                    message: L10n.errorUninstallTrashFailed(error.localizedDescription),
                    terminateAfter: true
                )
                return
            }
        }

        hud.show(
            success: true,
            title: L10n.hudUninstallTitle,
            subtitle: L10n.hudUninstallSubtitle,
            duration: 1.6
        ) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Install / Update Helper

    private func promptInstallHelper(
        isUpdate: Bool,
        installedVersion: String?,
        showWakeOption: Bool,
        terminateOnCancel: Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        if isUpdate {
            alert.messageText = L10n.updateAlertTitle
            alert.informativeText = L10n.updateAlertMessage(
                installed: installedVersion,
                current: RefreshDNSConstants.helperVersion
            )
            alert.addButton(withTitle: L10n.updateAlertConfirm)
        } else {
            alert.messageText = L10n.installAlertTitle
            alert.informativeText = L10n.installAlertMessage
            alert.addButton(withTitle: L10n.installAlertConfirm)
        }
        alert.addButton(withTitle: L10n.cancel)

        var wakeCheckbox: NSButton?
        if showWakeOption {
            let checkbox = NSButton(checkboxWithTitle: L10n.installAlertWakeCheckbox, target: nil, action: nil)
            checkbox.state = RefreshDNSPreferences.isWakeRefreshEnabled ? .on : .off
            checkbox.sizeToFit()
            alert.accessoryView = checkbox
            wakeCheckbox = checkbox
        }

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            completion(false)
            if terminateOnCancel {
                NSApp.terminate(nil)
            }
            return
        }

        let shouldEnableWake = (wakeCheckbox?.state == .on)

        HelperClient.shared.installHelper { result in
            Task { @MainActor in
                switch result {
                case .success:
                    if shouldEnableWake {
                        DispatchQueue.global(qos: .userInitiated).async {
                            _ = WakeAgentManager.shared.setWakeRefreshEnabled(true)
                            Task { @MainActor in
                                completion(true)
                            }
                        }
                    } else {
                        completion(true)
                    }
                case .cancelled:
                    completion(false)
                    if terminateOnCancel {
                        NSApp.terminate(nil)
                    }
                case .failure(let message):
                    completion(false)
                    self.showErrorAlert(
                        title: L10n.installFailedTitle,
                        message: message,
                        terminateAfter: terminateOnCancel
                    )
                }
            }
        }
    }

    // MARK: - Flush DNS

    private func performFlush(isWakeAuto: Bool) {
        let start = CFAbsoluteTimeGetCurrent()
        HelperClient.shared.flushDNS { result in
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            Task { @MainActor in
                switch result {
                case .success:
                    let subtitle = isWakeAuto
                        ? L10n.hudWakeSuccessSubtitle(ms: elapsedMs)
                        : L10n.hudSuccessSubtitle(ms: elapsedMs)
                    self.hud.show(
                        success: true,
                        title: L10n.hudSuccessTitle,
                        subtitle: subtitle,
                        duration: 1.35
                    ) {
                        NSApp.terminate(nil)
                    }
                case .failure(let message):
                    self.hud.show(
                        success: false,
                        title: L10n.hudFailureTitle,
                        subtitle: message,
                        duration: 2.6
                    ) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func showErrorAlert(title: String, message: String, terminateAfter: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
        if terminateAfter {
            NSApp.terminate(nil)
        }
    }
}

_ = CLIHandler.handleIfNeeded()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
