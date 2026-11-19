import Foundation

enum HelperStatus: Sendable {
    case ready
    case needsInstall
    case needsUpdate(String)
}

enum InstallResult: Sendable {
    case success
    case cancelled
    case failure(String)
}

enum FlushResult: Sendable {
    case success(String)
    case failure(String)
}

private final class ConnectionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    let connection: NSXPCConnection

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    func finishOnce(_ action: () -> Void) {
        lock.lock()
        let shouldRun = !completed
        if shouldRun {
            completed = true
        }
        lock.unlock()

        guard shouldRun else { return }
        connection.invalidate()
        action()
    }
}

final class HelperClient: Sendable {
    static let shared = HelperClient()

    private init() {}

    func checkHelperStatus(completion: @escaping @Sendable (HelperStatus) -> Void) {
        let guardBox = ConnectionGuard(connection: makeConnection())
        let connection = guardBox.connection

        let finish: @Sendable (HelperStatus) -> Void = { status in
            guardBox.finishOnce {
                completion(status)
            }
        }

        connection.invalidationHandler = {
            finish(.needsInstall)
        }
        connection.interruptionHandler = {
            finish(.needsInstall)
        }

        connection.resume()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) {
            finish(.needsInstall)
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            finish(.needsInstall)
        } as? RefreshDNSHelperProtocol

        guard let proxy else {
            finish(.needsInstall)
            return
        }

        proxy.getVersion { version in
            if version == RefreshDNSConstants.helperVersion {
                finish(.ready)
            } else {
                finish(.needsUpdate(version))
            }
        }
    }

    func flushDNS(completion: @escaping @Sendable (FlushResult) -> Void) {
        let guardBox = ConnectionGuard(connection: makeConnection())
        let connection = guardBox.connection

        let finish: @Sendable (FlushResult) -> Void = { result in
            guardBox.finishOnce {
                completion(result)
            }
        }

        connection.invalidationHandler = {
            finish(.failure(L10n.errorXPCInvalidated))
        }
        connection.interruptionHandler = {
            finish(.failure(L10n.errorXPCInterrupted))
        }

        connection.resume()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5.0) {
            finish(.failure(L10n.errorXPCTimeout))
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            finish(.failure(L10n.errorXPCCommunication(error.localizedDescription)))
        } as? RefreshDNSHelperProtocol

        guard let proxy else {
            finish(.failure(L10n.errorXPCProxy))
            return
        }

        proxy.flushDNS { success, message in
            if success {
                finish(.success(message))
            } else {
                finish(.failure(L10n.localizeHelperError(message)))
            }
        }
    }

    func installHelper(completion: @escaping @Sendable (InstallResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bundleURL = Bundle.main.bundleURL
            let helperSource = bundleURL.appendingPathComponent(RefreshDNSConstants.bundledHelperRelativePath).path
            let plistSource = bundleURL.appendingPathComponent(RefreshDNSConstants.bundledPlistRelativePath).path

            let fm = FileManager.default
            guard fm.fileExists(atPath: helperSource), fm.fileExists(atPath: plistSource) else {
                completion(.failure(L10n.errorInstallMissingFiles))
                return
            }

            let qHelperSrc = Self.shellQuote(helperSource)
            let qPlistSrc = Self.shellQuote(plistSource)
            let qHelperDst = Self.shellQuote(RefreshDNSConstants.installedHelperPath)
            let qPlistDst = Self.shellQuote(RefreshDNSConstants.installedPlistPath)
            let serviceTarget = "system/\(RefreshDNSConstants.machServiceName)"

            let shellScript = """
            set -e
            /bin/mkdir -p /Library/PrivilegedHelperTools
            /bin/cp -f \(qHelperSrc) \(qHelperDst)
            /usr/bin/xattr -cr \(qHelperDst) 2>/dev/null || true
            /usr/sbin/chown root:wheel \(qHelperDst)
            /bin/chmod 755 \(qHelperDst)
            /bin/cp -f \(qPlistSrc) \(qPlistDst)
            /usr/bin/xattr -cr \(qPlistDst) 2>/dev/null || true
            /usr/sbin/chown root:wheel \(qPlistDst)
            /bin/chmod 644 \(qPlistDst)
            if /bin/launchctl print \(serviceTarget) >/dev/null 2>&1; then
                /bin/launchctl bootout \(serviceTarget) >/dev/null 2>&1 || true
                /bin/sleep 0.2
            fi
            /bin/launchctl enable \(serviceTarget)
            /bin/launchctl bootstrap system \(qPlistDst)
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "on run argv",
                "-e", "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges",
                "-e", "end run",
                "--",
                shellScript,
                L10n.authPrompt
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    completion(.success)
                    return
                }

                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.contains("User canceled") || output.contains("-128") {
                    completion(.cancelled)
                } else {
                    completion(.failure(output.isEmpty ? L10n.errorInstallFailedCode(process.terminationStatus) : output))
                }
            } catch {
                completion(.failure(L10n.errorInstallLaunchFailed(error.localizedDescription)))
            }
        }
    }

    func uninstallHelper(completion: @escaping @Sendable (InstallResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let plistExists = fm.fileExists(atPath: RefreshDNSConstants.installedPlistPath)
            let helperExists = fm.fileExists(atPath: RefreshDNSConstants.installedHelperPath)
            let serviceTarget = "system/\(RefreshDNSConstants.machServiceName)"
            let serviceLoaded = Self.isLaunchdServiceLoaded(serviceTarget)

            if !plistExists && !helperExists && !serviceLoaded {
                completion(.success)
                return
            }

            let qHelperDst = Self.shellQuote(RefreshDNSConstants.installedHelperPath)
            let qPlistDst = Self.shellQuote(RefreshDNSConstants.installedPlistPath)

            let shellScript = """
            set -e
            if /bin/launchctl print \(serviceTarget) >/dev/null 2>&1; then
                /bin/launchctl bootout \(serviceTarget) >/dev/null 2>&1 || true
            fi
            /bin/rm -f \(qPlistDst) \(qHelperDst)
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "on run argv",
                "-e", "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges",
                "-e", "end run",
                "--",
                shellScript,
                L10n.authUninstallPrompt
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    completion(.success)
                    return
                }

                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.contains("User canceled") || output.contains("-128") {
                    completion(.cancelled)
                } else {
                    completion(.failure(output.isEmpty ? L10n.errorUninstallFailedCode(process.terminationStatus) : output))
                }
            } catch {
                completion(.failure(L10n.errorUninstallLaunchFailed(error.localizedDescription)))
            }
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: RefreshDNSConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: RefreshDNSHelperProtocol.self)
        return connection
    }

    private static func isLaunchdServiceLoaded(_ serviceTarget: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", serviceTarget]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
