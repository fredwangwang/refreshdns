import Foundation

public enum RefreshDNSConstants {
    public static let appBundleID = "me.wanghuan.refreshdns"
    public static let machServiceName = "me.wanghuan.refreshdns.helper"
    public static let helperVersion = "1.0.0"

    public static let installedHelperPath = "/Library/PrivilegedHelperTools/me.wanghuan.refreshdns.helper"
    public static let installedPlistPath = "/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist"

    public static let bundledHelperRelativePath = "Contents/Library/HelperTools/me.wanghuan.refreshdns.helper"
    public static let bundledPlistRelativePath = "Contents/Library/LaunchDaemons/me.wanghuan.refreshdns.helper.plist"
}

@objc(RefreshDNSHelperProtocol)
public protocol RefreshDNSHelperProtocol {
    func getVersion(withReply reply: @escaping @Sendable (String) -> Void)
    func flushDNS(withReply reply: @escaping @Sendable (Bool, String) -> Void)
}
