import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt

private enum IOMessage {
    // From <IOKit/IOMessage.h>: iokit_common_msg(x) = (UInt32)(0xE0000000 | x)
    static let canSystemSleep: UInt32 = 0xE0000270
    static let systemWillSleep: UInt32 = 0xE0000280
    static let systemHasPoweredOn: UInt32 = 0xE0000300
}

private final class XPCConnectionGuard: @unchecked Sendable {
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

private func powerCallback(
    refCon: UnsafeMutableRawPointer?,
    service: io_service_t,
    messageType: natural_t,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard let refCon else { return }
    let monitor = Unmanaged<WakeMonitor>.fromOpaque(refCon).takeUnretainedValue()
    monitor.handlePowerMessage(messageType: messageType, messageArgument: messageArgument)
}

final class WakeMonitor: @unchecked Sendable {
    private let powerQueue = DispatchQueue(label: "me.wanghuan.refreshdns.wakeagent.power")
    private let workQueue = DispatchQueue(label: "me.wanghuan.refreshdns.wakeagent.work")

    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    private var pendingWorkItem: DispatchWorkItem?
    private var lastFlushTime: CFAbsoluteTime = 0

    func start() -> Bool {
        var portRef: IONotificationPortRef?
        var notifierObj: io_object_t = 0

        let refCon = Unmanaged.passUnretained(self).toOpaque()
        let port = IORegisterForSystemPower(refCon, &portRef, powerCallback, &notifierObj)
        guard port != 0, let validNotifyPort = portRef else {
            return false
        }

        rootPort = port
        notifyPort = validNotifyPort
        notifier = notifierObj

        IONotificationPortSetDispatchQueue(validNotifyPort, powerQueue)
        return true
    }

    func stop() {
        workQueue.sync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
        }

        if notifier != 0 {
            IODeregisterForSystemPower(&notifier)
            notifier = 0
        }
        if rootPort != 0 {
            IOServiceClose(rootPort)
            rootPort = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
    }

    fileprivate func handlePowerMessage(messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
        switch messageType {
        case IOMessage.canSystemSleep:
            if rootPort != 0 {
                IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
            }
        case IOMessage.systemWillSleep:
            cancelPendingWakeFlush()
            if rootPort != 0 {
                IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
            }
        case IOMessage.systemHasPoweredOn:
            scheduleWakeFlush()
        default:
            break
        }
    }

    private func cancelPendingWakeFlush() {
        workQueue.async { [weak self] in
            self?.pendingWorkItem?.cancel()
            self?.pendingWorkItem = nil
        }
    }

    private func scheduleWakeFlush() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.pendingWorkItem?.cancel()

            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingWorkItem = nil

                let now = CFAbsoluteTimeGetCurrent()
                guard now - self.lastFlushTime >= RefreshDNSConstants.wakeDebounceSeconds else {
                    return
                }
                self.lastFlushTime = now

                self.executeWakeRefresh(completion: {})
            }

            self.pendingWorkItem = item
            self.workQueue.asyncAfter(
                deadline: .now() + RefreshDNSConstants.wakeFlushDelaySeconds,
                execute: item
            )
        }
    }

    func executeWakeRefresh(completion: @escaping @Sendable () -> Void) {
        guard RefreshDNSPreferences.isWakeRefreshEnabled else {
            completion()
            return
        }

        if RefreshDNSPreferences.showHUDOnWake, let appExecPath = resolveMainAppExecutablePath() {
            launchAppForWakeFlush(executablePath: appExecPath, completion: completion)
        } else {
            flushDNSSilently(completion: completion)
        }
    }

    private func resolveMainAppExecutablePath() -> String? {
        // Expected path: <App>.app/Contents/Library/HelperTools/me.wanghuan.refreshdns.wakeagent
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let contentsURL = executableURL
            .deletingLastPathComponent() // HelperTools
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
        let mainExecURL = contentsURL.appendingPathComponent("MacOS/RefreshDNS")
        guard FileManager.default.isExecutableFile(atPath: mainExecURL.path) else {
            return nil
        }
        return mainExecURL.path
    }

    private func launchAppForWakeFlush(executablePath: String, completion: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["--wake-flush"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Fallback to silent XPC flush if launching the app fails
                self.flushDNSSilently(completion: completion)
                return
            }
            completion()
        }
    }

    private func flushDNSSilently(completion: @escaping @Sendable () -> Void) {
        let connection = NSXPCConnection(
            machServiceName: RefreshDNSConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: RefreshDNSHelperProtocol.self)

        let guardBox = XPCConnectionGuard(connection: connection)
        let finish: @Sendable () -> Void = {
            guardBox.finishOnce {
                completion()
            }
        }

        connection.invalidationHandler = { finish() }
        connection.interruptionHandler = { finish() }
        connection.resume()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) {
            finish()
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            finish()
        }) as? RefreshDNSHelperProtocol else {
            finish()
            return
        }

        proxy.flushDNS { _, _ in
            finish()
        }
    }
}

let monitor = WakeMonitor()

if CommandLine.arguments.contains("--trigger-once") {
    let semaphore = DispatchSemaphore(value: 0)
    monitor.executeWakeRefresh {
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 10.0)
    exit(0)
}

guard monitor.start() else {
    fputs("RefreshDNSWakeAgent: failed to register for IOKit system power notifications.\n", stderr)
    exit(1)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)

let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    monitor.stop()
    exit(0)
}
termSource.resume()

let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSource.setEventHandler {
    monitor.stop()
    exit(0)
}
intSource.resume()

dispatchMain()
