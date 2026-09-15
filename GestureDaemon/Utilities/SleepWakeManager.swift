import Cocoa

public final class SleepWakeManager {
    public static let shared = SleepWakeManager()

    private var isStarted = false

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let notificationCenter = NSWorkspace.shared.notificationCenter

        // 1. System Sleep Notification
        notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        // 2. System Wake Notification
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // 3. Screen / Display Sleep Notification
        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensDidSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        // 4. Screen / Display Wake Notification
        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        Log.info("SleepWakeManager active (monitoring system and screen power transitions).")
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        Log.info("💤 NSWorkspace willSleepNotification received.")
        EventTapManager.shared.resetState()
        HIDPlusPlusManager.shared.handleSleep()
    }

    @objc private func handleDidWake(_ notification: Notification) {
        Log.info("☀️ NSWorkspace didWakeNotification received.")
        EventTapManager.shared.resetState()
        EventTapManager.shared.ensureTapActive()
        HIDPlusPlusManager.shared.handleWake()
    }

    @objc private func handleScreensDidSleep(_ notification: Notification) {
        Log.info("💤 NSWorkspace screensDidSleepNotification received.")
        EventTapManager.shared.resetState()
    }

    @objc private func handleScreensDidWake(_ notification: Notification) {
        Log.info("☀️ NSWorkspace screensDidWakeNotification received.")
        EventTapManager.shared.resetState()
        EventTapManager.shared.ensureTapActive()
        HIDPlusPlusManager.shared.handleWake()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
