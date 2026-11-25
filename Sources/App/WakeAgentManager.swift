import Darwin
import Foundation

enum WakeAgentError: Error, Sendable {
    case missingBinary
    case plistWriteFailed(String)
    case launchctlFailed(String)

    var localizedMessage: String {
        switch self {
        case .missingBinary:
            return L10n.errorWakeMissingBinary
        case .plistWriteFailed(let detail):
            return L10n.errorWakePlistFailed(detail)
        case .launchctlFailed(let detail):
            return L10n.errorWakeLaunchctlFailed(detail)
        }
    }
}

final class WakeAgentManager: Sendable {
    static let shared = WakeAgentManager()

    private init() {}

    var domainTarget: String {
        "gui/\(getuid())"
    }

    var serviceTarget: String {
        "\(domainTarget)/\(RefreshDNSConstants.wakeAgentLabel)"
    }

    var plistPath: String {
        RefreshDNSConstants.installedWakeAgentPlistPath
    }

    var bundledWakeAgentPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent(RefreshDNSConstants.bundledWakeAgentRelativePath)
            .path
    }

    var isAgentLoaded: Bool {
        runLaunchctl(["print", serviceTarget]).status == 0
    }

    var isWakeRefreshActive: Bool {
        RefreshDNSPreferences.isWakeRefreshEnabled
            && FileManager.default.fileExists(atPath: plistPath)
    }

    @discardableResult
    func setWakeRefreshEnabled(_ enabled: Bool) -> Result<Void, WakeAgentError> {
        let fm = FileManager.default

        if enabled {
            let wakeAgentPath = bundledWakeAgentPath
            guard fm.isExecutableFile(atPath: wakeAgentPath) else {
                return .failure(.missingBinary)
            }

            let launchAgentsDir = URL(fileURLWithPath: plistPath).deletingLastPathComponent()
            do {
                try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            } catch {
                return .failure(.plistWriteFailed(error.localizedDescription))
            }

            let plist: [String: Any] = [
                "Label": RefreshDNSConstants.wakeAgentLabel,
                "AssociatedBundleIdentifiers": [RefreshDNSConstants.appBundleID],
                "ProgramArguments": [wakeAgentPath],
                "RunAtLoad": true,
                "KeepAlive": [
                    "PathState": [
                        wakeAgentPath: true
                    ]
                ],
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Background",
            ]

            do {
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist,
                    format: .xml,
                    options: 0
                )
                try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
            } catch {
                return .failure(.plistWriteFailed(error.localizedDescription))
            }

            RefreshDNSPreferences.isWakeRefreshEnabled = true

            if isAgentLoaded {
                _ = runLaunchctl(["bootout", serviceTarget])
                Thread.sleep(forTimeInterval: 0.15)
            }

            _ = runLaunchctl(["enable", serviceTarget])
            let bootstrap = runLaunchctl(["bootstrap", domainTarget, plistPath])
            if bootstrap.status != 0 {
                RefreshDNSPreferences.isWakeRefreshEnabled = false
                try? fm.removeItem(atPath: plistPath)
                let detail = bootstrap.output.isEmpty
                    ? "exit code \(bootstrap.status)"
                    : bootstrap.output
                return .failure(.launchctlFailed(detail))
            }

            return .success(())
        } else {
            RefreshDNSPreferences.isWakeRefreshEnabled = false
            if isAgentLoaded {
                _ = runLaunchctl(["bootout", serviceTarget])
            }
            if fm.fileExists(atPath: plistPath) {
                try? fm.removeItem(atPath: plistPath)
            }
            return .success(())
        }
    }

    func syncInstalledPathIfNeeded() {
        guard RefreshDNSPreferences.isWakeRefreshEnabled else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        guard FileManager.default.isExecutableFile(atPath: bundledWakeAgentPath) else { return }

        var needsReload = !isAgentLoaded
        if let data = FileManager.default.contents(atPath: plistPath),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let args = dict["ProgramArguments"] as? [String],
           args.first == bundledWakeAgentPath {
            // Path matches current app bundle
        } else {
            needsReload = true
        }

        if needsReload {
            _ = setWakeRefreshEnabled(true)
        }
    }

    func uninstallWakeAgent() {
        _ = setWakeRefreshEnabled(false)
        RefreshDNSPreferences.removeAll()
        let prefPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(RefreshDNSConstants.appBundleID).plist")
            .path
        if FileManager.default.fileExists(atPath: prefPath) {
            try? FileManager.default.removeItem(atPath: prefPath)
        }
    }

    private func runLaunchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
