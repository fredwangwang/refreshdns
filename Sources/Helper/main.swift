import Foundation

final class HelperService: NSObject, NSXPCListenerDelegate, RefreshDNSHelperProtocol, @unchecked Sendable {
    private let workQueue = DispatchQueue(label: "me.wanghuan.refreshdns.helper.work")
    private let stateQueue = DispatchQueue(label: "me.wanghuan.refreshdns.helper.state")
    private var activeRequests = 0
    private var idleShutdownWorkItem: DispatchWorkItem?
    private let idleTimeoutSeconds: TimeInterval = 15.0

    override init() {
        super.init()
        scheduleIdleShutdown()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: RefreshDNSHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - RefreshDNSHelperProtocol

    func getVersion(withReply reply: @escaping @Sendable (String) -> Void) {
        beginRequest()
        defer { endRequest() }
        reply(RefreshDNSConstants.helperVersion)
    }

    func flushDNS(withReply reply: @escaping @Sendable (Bool, String) -> Void) {
        beginRequest()
        workQueue.async { [weak self] in
            guard let self else {
                reply(false, "ERR_UNAVAILABLE")
                return
            }
            defer { self.endRequest() }

            guard geteuid() == 0 else {
                reply(false, "ERR_NOT_ROOT|\(geteuid())")
                return
            }

            let step1 = self.runTool(path: "/usr/bin/dscacheutil", arguments: ["-flushcache"])
            guard step1.status == 0 else {
                reply(false, "ERR_DSCACHEUTIL|\(step1.status)|\(step1.output)")
                return
            }

            let step2 = self.runTool(path: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
            guard step2.status == 0 else {
                reply(false, "ERR_MDNS|\(step2.status)|\(step2.output)")
                return
            }

            reply(true, "OK")
        }
    }

    // MARK: - Private

    private func beginRequest() {
        stateQueue.sync {
            activeRequests += 1
            idleShutdownWorkItem?.cancel()
            idleShutdownWorkItem = nil
        }
    }

    private func endRequest() {
        stateQueue.sync {
            activeRequests = max(0, activeRequests - 1)
            if activeRequests == 0 {
                scheduleIdleShutdownLocked()
            }
        }
    }

    private func scheduleIdleShutdown() {
        stateQueue.sync {
            scheduleIdleShutdownLocked()
        }
    }

    private func scheduleIdleShutdownLocked() {
        idleShutdownWorkItem?.cancel()
        let item = DispatchWorkItem {
            exit(0)
        }
        idleShutdownWorkItem = item
        stateQueue.asyncAfter(deadline: .now() + idleTimeoutSeconds, execute: item)
    }

    private func runTool(path: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: RefreshDNSConstants.machServiceName)
listener.delegate = service
listener.resume()

dispatchMain()
