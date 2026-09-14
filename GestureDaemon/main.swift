import Cocoa

let args = CommandLine.arguments
let isDiagnostics = args.contains("--diagnostics")

Log.info("Launching GestureDaemon...")

if isDiagnostics {
    Log.info("DIAGNOSTIC mode: button indices will print to stdout.")
    EventTapManager.shared.enableDiagnostics(true)
}

_ = ConfigManager.shared

if !AccessibilityHelper.verifyAccessibility(prompt: true) {
    Log.error("Accessibility permission missing. System prompt shown.")
}

AccessibilityHelper.pollForAccess {
    Log.info("Starting EventTap...")
    EventTapManager.shared.start()
    HIDPlusPlusManager.shared.start()
}

// [FIX] Graceful shutdown so `stop()` actually runs instead of the process
// being killed mid-tap by launchd/SIGTERM.
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

