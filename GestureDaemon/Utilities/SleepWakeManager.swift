import Cocoa

public final class SleepWakeManager: NSObject {
    public static let shared = SleepWakeManager()

    private var isStarted = false
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter

        // 1. System Sleep Notification
        let sleepObs = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("💤 NSWorkspace willSleepNotification received.")
            self?.handleSleep()
        }
        observers.append(sleepObs)

        // 2. System Wake Notification
        let wakeObs = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("☀️ NSWorkspace didWakeNotification received.")
            self?.handleWake()
        }
        observers.append(wakeObs)

        // 3. Screen / Display Sleep Notification
        let screenSleepObs = center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("💤 NSWorkspace screensDidSleepNotification received.")
            self?.handleSleep()
        }
        observers.append(screenSleepObs)

        // 4. Screen / Display Wake Notification
        let screenWakeObs = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("☀️ NSWorkspace screensDidWakeNotification received.")
            self?.handleWake()
        }
        observers.append(screenWakeObs)

        // 5. Fast User Switching / Screen Lock Session transitions
        let lockObs = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("🔒 NSWorkspace sessionDidResignActiveNotification received.")
            self?.handleSleep()
        }
        observers.append(lockObs)

        let unlockObs = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Log.info("🔓 NSWorkspace sessionDidBecomeActiveNotification received.")
            self?.handleWake()
        }
        observers.append(unlockObs)

        Log.info("SleepWakeManager active (monitoring system, screen, and session power transitions).")
    }

    private func handleSleep() {
        EventTapManager.shared.resetState()
        HIDPlusPlusManager.shared.handleSleep()
    }

    private func handleWake() {
        EventTapManager.shared.resetState()
        EventTapManager.shared.ensureTapActive()
        HIDPlusPlusManager.shared.handleWake()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for obs in observers {
            center.removeObserver(obs)
        }
        observers.removeAll()
    }
}
