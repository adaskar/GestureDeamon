import Cocoa

public final class SleepWakeManager: NSObject {
    public static let shared = SleepWakeManager()

    private var isStarted = false
    private var observers: [NSObjectProtocol] = []
    private var lastDisplayWakeTime: CFAbsoluteTime = 0.0
    private var lastSystemWakeTime: CFAbsoluteTime = 0.0

    private override init() {
        super.init()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter

        // 1. System Sleep Notification (Mac goes to ACPI S3/S0ix sleep)
        let sleepObs = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("💤 NSWorkspace willSleepNotification received.")
            self?.handleSystemSleep()
        }
        observers.append(sleepObs)

        // 2. System Wake Notification (Mac wakes from full system sleep)
        let wakeObs = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("☀️ NSWorkspace didWakeNotification received.")
            self?.handleSystemWake()
        }
        observers.append(wakeObs)

        // 3. Screen / Display Sleep Notification (Monitor turns off, but Mac stays awake)
        let screenSleepObs = center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("💤 NSWorkspace screensDidSleepNotification received.")
            self?.handleDisplaySleep()
        }
        observers.append(screenSleepObs)

        // 4. Screen / Display Wake Notification (Monitor turns on, Mac was already awake)
        let screenWakeObs = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("☀️ NSWorkspace screensDidWakeNotification received.")
            self?.handleDisplayWake()
        }
        observers.append(screenWakeObs)

        // 5. Fast User Switching / Screen Lock Session transitions
        let lockObs = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("🔒 NSWorkspace sessionDidResignActiveNotification received.")
            self?.handleDisplaySleep()
        }
        observers.append(lockObs)

        let unlockObs = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("🔓 NSWorkspace sessionDidBecomeActiveNotification received.")
            self?.handleDisplayWake()
        }
        observers.append(unlockObs)

        Log.info("SleepWakeManager active (monitoring system, screen, and session power transitions).")
    }

    private func handleSystemSleep() {
        EventTapManager.shared.resetState()
        HIDPlusPlusManager.shared.handleSleep()
    }

    private func handleSystemWake() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSystemWakeTime > 0.5 else { return }
        lastSystemWakeTime = now

        EventTapManager.shared.resetState()
        EventTapManager.shared.ensureTapActive()
        HIDPlusPlusManager.shared.handleWake()
    }

    private func handleDisplaySleep() {
        EventTapManager.shared.resetState()
        HIDPlusPlusManager.shared.handleSleep()
    }

    private func handleDisplayWake() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDisplayWakeTime > 0.5 else { return }
        lastDisplayWakeTime = now

        EventTapManager.shared.resetState()
        EventTapManager.shared.ensureTapActive()
        HIDPlusPlusManager.shared.handleDisplayWake()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for obs in observers {
            center.removeObserver(obs)
        }
        observers.removeAll()
    }
}
