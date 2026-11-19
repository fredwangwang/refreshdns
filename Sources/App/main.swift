import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hud = HUDWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shouldUninstall = CommandLine.arguments.contains("--uninstall")
            || NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)

        if shouldUninstall {
            promptUninstall()
            return
        }

        HelperClient.shared.checkHelperStatus { status in
            Task { @MainActor in
                switch status {
                case .ready:
                    self.performFlush()
                case .needsInstall:
                    self.promptInstallHelper(isUpdate: false, installedVersion: nil)
                case .needsUpdate(let oldVersion):
                    self.promptInstallHelper(isUpdate: true, installedVersion: oldVersion)
                }
            }
        }
    }

    private func promptUninstall() {
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
            NSApp.terminate(nil)
            return
        }

        HelperClient.shared.uninstallHelper { result in
            Task { @MainActor in
                switch result {
                case .success:
                    self.trashAppBundleAndFinish()
                case .cancelled:
                    NSApp.terminate(nil)
                case .failure(let message):
                    self.showErrorAlert(title: L10n.uninstallFailedTitle, message: message)
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
                    message: L10n.errorUninstallTrashFailed(error.localizedDescription)
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

    private func promptInstallHelper(isUpdate: Bool, installedVersion: String?) {
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

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        HelperClient.shared.installHelper { result in
            Task { @MainActor in
                switch result {
                case .success:
                    self.performFlush()
                case .cancelled:
                    NSApp.terminate(nil)
                case .failure(let message):
                    self.showErrorAlert(title: L10n.installFailedTitle, message: message)
                }
            }
        }
    }

    private func performFlush() {
        let start = CFAbsoluteTimeGetCurrent()
        HelperClient.shared.flushDNS { result in
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            Task { @MainActor in
                switch result {
                case .success:
                    self.hud.show(
                        success: true,
                        title: L10n.hudSuccessTitle,
                        subtitle: L10n.hudSuccessSubtitle(ms: elapsedMs),
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

    private func showErrorAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
