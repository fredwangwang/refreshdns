import Foundation

enum L10n {
    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    private static func trFormat(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }

    // Alerts
    static var installAlertTitle: String { tr("alert.install.title") }
    static var installAlertMessage: String { tr("alert.install.message") }
    static var installAlertConfirm: String { tr("alert.install.confirm") }

    static var updateAlertTitle: String { tr("alert.update.title") }
    static func updateAlertMessage(installed: String?, current: String) -> String {
        trFormat("alert.update.message", installed ?? tr("alert.update.unknown_version"), current)
    }
    static var updateAlertConfirm: String { tr("alert.update.confirm") }

    static var installFailedTitle: String { tr("alert.install_failed.title") }
    static var uninstallAlertTitle: String { tr("alert.uninstall.title") }
    static var uninstallAlertMessage: String { tr("alert.uninstall.message") }
    static var uninstallAlertConfirm: String { tr("alert.uninstall.confirm") }
    static var uninstallFailedTitle: String { tr("alert.uninstall_failed.title") }
    static var cancel: String { tr("button.cancel") }
    static var ok: String { tr("button.ok") }

    // HUD
    static var hudSuccessTitle: String { tr("hud.success.title") }
    static func hudSuccessSubtitle(ms: Int) -> String {
        trFormat("hud.success.subtitle", ms)
    }
    static var hudFailureTitle: String { tr("hud.failure.title") }
    static var hudUninstallTitle: String { tr("hud.uninstall.title") }
    static var hudUninstallSubtitle: String { tr("hud.uninstall.subtitle") }

    // Auth & XPC errors
    static var authPrompt: String { tr("auth.prompt") }
    static var authUninstallPrompt: String { tr("auth.uninstall_prompt") }
    static var errorXPCInvalidated: String { tr("error.xpc.invalidated") }
    static var errorXPCInterrupted: String { tr("error.xpc.interrupted") }
    static var errorXPCTimeout: String { tr("error.xpc.timeout") }
    static func errorXPCCommunication(_ detail: String) -> String {
        trFormat("error.xpc.communication", detail)
    }
    static var errorXPCProxy: String { tr("error.xpc.proxy") }
    static var errorInstallMissingFiles: String { tr("error.install.missing_files") }
    static func errorInstallFailedCode(_ code: Int32) -> String {
        trFormat("error.install.failed_code", code)
    }
    static func errorInstallLaunchFailed(_ detail: String) -> String {
        trFormat("error.install.launch_failed", detail)
    }
    static func errorUninstallFailedCode(_ code: Int32) -> String {
        trFormat("error.uninstall.failed_code", code)
    }
    static func errorUninstallLaunchFailed(_ detail: String) -> String {
        trFormat("error.uninstall.launch_failed", detail)
    }
    static func errorUninstallTrashFailed(_ detail: String) -> String {
        trFormat("error.uninstall.trash_failed", detail)
    }

    static func localizeHelperError(_ raw: String) -> String {
        let parts = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "ERR_UNAVAILABLE":
            return tr("error.helper.unavailable")
        case "ERR_NOT_ROOT" where parts.count >= 2:
            return trFormat("error.helper.not_root", parts[1])
        case "ERR_DSCACHEUTIL" where parts.count >= 3:
            return trFormat("error.helper.dscacheutil", parts[1], parts[2])
        case "ERR_MDNS" where parts.count >= 3:
            return trFormat("error.helper.mdns", parts[1], parts[2])
        default:
            return raw
        }
    }
}
