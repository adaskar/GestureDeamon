import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("GestureDaemon application did finish launching.")

        _ = ConfigManager.shared
        MenuBarController.shared.setup()

        if !AccessibilityHelper.verifyAccessibility(prompt: true) {
            Log.error("Accessibility permission missing. System prompt shown.")
        }

        AccessibilityHelper.pollForAccess {
            Log.info("Accessibility granted. Starting event taps and hardware drivers...")
            EventTapManager.shared.start()
            HIDPlusPlusManager.shared.start()
        }

        // Install graceful SIGTERM handler
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigtermSource.setEventHandler {
            Log.info("SIGTERM received. Terminating application.")
            EventTapManager.shared.stop()
            HIDPlusPlusManager.shared.stop()
            NSApplication.shared.terminate(nil)
        }
        sigtermSource.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("GestureDaemon terminating...")
        EventTapManager.shared.stop()
        HIDPlusPlusManager.shared.stop()
    }
}

let args = CommandLine.arguments
let isDiagnostics = args.contains("--diagnostics")

if isDiagnostics {
    Log.info("Launching GestureDaemon in DIAGNOSTIC mode...")
    EventTapManager.shared.enableDiagnostics(true)

    _ = ConfigManager.shared

    if !AccessibilityHelper.verifyAccessibility(prompt: true) {
        Log.error("Accessibility permission missing. System prompt shown.")
    }

    AccessibilityHelper.pollForAccess {
        Log.info("Starting EventTap...")
        EventTapManager.shared.start()
        HIDPlusPlusManager.shared.start()
    }

    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    signal(SIGTERM, SIG_IGN)
    sigtermSource.setEventHandler {
        Log.info("SIGTERM received. Shutting down.")
        EventTapManager.shared.stop()
        HIDPlusPlusManager.shared.stop()
        exit(0)
    }
    sigtermSource.resume()

    while RunLoop.current.run(mode: .default, before: .distantFuture) {}
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
