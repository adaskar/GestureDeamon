import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ConfigManager.shared
        Log.info("GestureDaemon application did finish launching.")

        MenuBarController.shared.setup()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.guru.GestureDaemon.reopen"),
            object: nil, queue: .main
        ) { _ in
            MenuBarController.shared.handleAppReopen()
        }

        PermissionHelper.verifyAndPrompt()

        AccessibilityHelper.pollForAccess {
            Log.info("Accessibility granted. Starting event taps and hardware drivers...")
            EventTapManager.shared.start()
            HIDPlusPlusManager.shared.start()
            ScrollManager.shared.start()
            SleepWakeManager.shared.start()
        }

        // Install graceful SIGTERM handler
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigtermSource.setEventHandler {
            Log.info("SIGTERM received. Terminating application.")
            EventTapManager.shared.stop()
            HIDPlusPlusManager.shared.stop()
            ScrollManager.shared.stop()
            NSApplication.shared.terminate(nil)
        }
        sigtermSource.resume()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarController.shared.handleAppReopen()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if MenuBarController.shared.isTemporarilyVisible || !MenuBarController.shared.hasVisibleStatusItem {
            MenuBarController.shared.handleAppReopen()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("GestureDaemon terminating...")
        EventTapManager.shared.stop()
        HIDPlusPlusManager.shared.stop()
        ScrollManager.shared.stop()
    }
}

let args = CommandLine.arguments

if args.contains("--version") || args.contains("-v") {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    print("GestureDaemon v\(version) (build \(build))")
    exit(0)
}

if args.contains("--help") || args.contains("-h") {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    print("""
    GestureDaemon v\(version) - Ultra-low latency macOS mouse gestures daemon

    Usage:
      GestureDaemon              Launch background daemon and menu bar status item
      GestureDaemon --diagnostics Run in foreground with verbose real-time logging
      GestureDaemon --version     Print version information and exit
      GestureDaemon --help        Show this help message and exit
    """)
    exit(0)
}

let isDiagnostics = args.contains("--diagnostics")

if isDiagnostics {
    Log.isEnabled = true
    Log.currentLevel = .debug
    Log.info("Launching GestureDaemon in DIAGNOSTIC mode...")
    EventTapManager.shared.enableDiagnostics(true)

    _ = ConfigManager.shared

    PermissionHelper.verifyAndPrompt()

    AccessibilityHelper.pollForAccess {
        Log.info("Starting EventTap and HID++ Manager...")
        EventTapManager.shared.start()
        HIDPlusPlusManager.shared.start()
        ScrollManager.shared.start()
        SleepWakeManager.shared.start()
    }

    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    signal(SIGTERM, SIG_IGN)
    sigtermSource.setEventHandler {
        Log.info("SIGTERM received. Shutting down.")
        EventTapManager.shared.stop()
        HIDPlusPlusManager.shared.stop()
        ScrollManager.shared.stop()
        exit(0)
    }
    sigtermSource.resume()

    while RunLoop.current.run(mode: .default, before: .distantFuture) {}
} else {
    // Single instance check: if already running, signal existing instance to show menu and exit
    let bundleId = Bundle.main.bundleIdentifier ?? "com.guru.GestureDaemon"
    let currentPid = ProcessInfo.processInfo.processIdentifier
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    let otherInstances = runningApps.filter { $0.processIdentifier != currentPid }

    if !otherInstances.isEmpty {
        Log.info("GestureDaemon is already running (PID: \(otherInstances.first?.processIdentifier ?? 0)). Signaling existing instance...")
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.guru.GestureDaemon.reopen"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        otherInstances.first?.activate(options: .activateIgnoringOtherApps)
        exit(0)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
