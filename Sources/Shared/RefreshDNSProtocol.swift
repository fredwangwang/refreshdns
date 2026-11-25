import Foundation

public enum RefreshDNSConstants {
    public static let appBundleID = "me.wanghuan.refreshdns"
    public static let machServiceName = "me.wanghuan.refreshdns.helper"
    public static let helperVersion = "1.0.0"

    public static let installedHelperPath = "/Library/PrivilegedHelperTools/me.wanghuan.refreshdns.helper"
    public static let installedPlistPath = "/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist"

    public static let bundledHelperRelativePath = "Contents/Library/HelperTools/me.wanghuan.refreshdns.helper"
    public static let bundledPlistRelativePath = "Contents/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist"

    public static let wakeAgentLabel = "me.wanghuan.refreshdns.wakeagent"
    public static let bundledWakeAgentRelativePath = "Contents/Library/HelperTools/me.wanghuan.refreshdns.wakeagent"
    public static let wakeFlushDelaySeconds: TimeInterval = 2.0
    public static let wakeDebounceSeconds: TimeInterval = 5.0

    public static var installedWakeAgentPlistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(wakeAgentLabel).plist")
            .path
    }
}

public enum RefreshDNSPreferences {
    private static let domain = RefreshDNSConstants.appBundleID as CFString
    private static let wakeRefreshEnabledKey = "wakeRefreshEnabled" as CFString
    private static let showHUDOnWakeKey = "showHUDOnWake" as CFString

    public static var isWakeRefreshEnabled: Bool {
        get {
            CFPreferencesAppSynchronize(domain)
            guard let raw = CFPreferencesCopyAppValue(wakeRefreshEnabledKey, domain) else {
                return false
            }
            return (raw as? NSNumber)?.boolValue ?? false
        }
        set {
            CFPreferencesSetAppValue(
                wakeRefreshEnabledKey,
                newValue ? kCFBooleanTrue : kCFBooleanFalse,
                domain
            )
            CFPreferencesAppSynchronize(domain)
        }
    }

    public static var showHUDOnWake: Bool {
        get {
            CFPreferencesAppSynchronize(domain)
            guard let raw = CFPreferencesCopyAppValue(showHUDOnWakeKey, domain) else {
                return true
            }
            return (raw as? NSNumber)?.boolValue ?? true
        }
        set {
            CFPreferencesSetAppValue(
                showHUDOnWakeKey,
                newValue ? kCFBooleanTrue : kCFBooleanFalse,
                domain
            )
            CFPreferencesAppSynchronize(domain)
        }
    }

    public static func removeAll() {
        CFPreferencesSetAppValue(wakeRefreshEnabledKey, nil, domain)
        CFPreferencesSetAppValue(showHUDOnWakeKey, nil, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

@objc(RefreshDNSHelperProtocol)
public protocol RefreshDNSHelperProtocol {
    func getVersion(withReply reply: @escaping @Sendable (String) -> Void)
    func flushDNS(withReply reply: @escaping @Sendable (Bool, String) -> Void)
}
