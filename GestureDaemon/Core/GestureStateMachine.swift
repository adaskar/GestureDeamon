import Foundation
import CoreGraphics

public enum GestureDirection { case left, right, up, down }

public enum CalibrationEvent {
    case triggerState(isDown: Bool, buttonIndex: Int)
    case motionUpdated(dx: Double, dy: Double, distance: Double)
    case directionDetected(GestureDirection, ActionDefinition?)
    case gestureCompleted(wasClick: Bool, ActionDefinition?)
    case otherButton(buttonIndex: Int, isDown: Bool, actionName: String?)
}

public final class GestureStateMachine {
    private var isTriggerEngaged = false
    private var accumulatedDeltaX: Double = 0.0
    private var accumulatedDeltaY: Double = 0.0
    private var gestureConsumed = false

    private var magicGestureTimer: DispatchSourceTimer?
    private var buttonSafetyTimer: DispatchSourceTimer?

    public var isEngaged: Bool { isTriggerEngaged }
    public var onEngagementChanged: ((Bool) -> Void)?

    // Live Calibration Mode (for Preferences window Live Tester)
    public var isCalibrationMode: Bool = false
    public var onCalibrationEvent: ((CalibrationEvent) -> Void)?

    public init() {}

    public func reset() {
        magicGestureTimer?.cancel()
        magicGestureTimer = nil
        buttonSafetyTimer?.cancel()
        buttonSafetyTimer = nil
        isTriggerEngaged = false
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(false)
    }

    public func handleMagicDown(windowDurationMs: Double = 200.0) -> Bool {
        isTriggerEngaged = true
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(true)
        Log.info("Magic thumb button engaged (waiting for flick gesture or click timeout)...")

        if isCalibrationMode {
            onCalibrationEvent?(.triggerState(isDown: true, buttonIndex: 5))
        }

        magicGestureTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Provide sufficient window in calibration mode, but ALWAYS timeout to guarantee zero motion overhead
        let duration = isCalibrationMode ? max(windowDurationMs, 300.0) : windowDurationMs
        timer.schedule(deadline: .now() + (duration / 1000.0))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTriggerEngaged else { return }
            if self.isCalibrationMode {
                let action = ConfigManager.shared.effectiveAction(for: .click)
                if !self.gestureConsumed {
                    self.onCalibrationEvent?(.gestureCompleted(wasClick: true, action))
                }
                self.onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: 5))
            } else if !self.gestureConsumed {
                Log.info("Click detected on magic thumb button (stationary tap)")
                let action = ConfigManager.shared.effectiveAction(for: .click)
                ActionDispatcher.shared.dispatch(action: action)
            }
            self.isTriggerEngaged = false
            self.accumulatedDeltaX = 0.0
            self.accumulatedDeltaY = 0.0
            self.gestureConsumed = false
            self.onEngagementChanged?(false)
        }
        timer.resume()
        self.magicGestureTimer = timer
        return true
    }

    public func handleMagicUp() -> Bool {
        guard isTriggerEngaged else {
            if isCalibrationMode {
                onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: 5))
            }
            return true
        }
        magicGestureTimer?.cancel()
        magicGestureTimer = nil

        if isCalibrationMode {
            let action: ActionDefinition?
            if !gestureConsumed {
                action = ConfigManager.shared.effectiveAction(for: .click)
                onCalibrationEvent?(.gestureCompleted(wasClick: true, action))
            } else {
                let dir = resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY)
                action = actionForDirection(dir)
                onCalibrationEvent?(.gestureCompleted(wasClick: false, action))
            }
            onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: 5))
            isTriggerEngaged = false
            accumulatedDeltaX = 0.0
            accumulatedDeltaY = 0.0
            gestureConsumed = false
            onEngagementChanged?(false)
            return true
        }

        if !gestureConsumed {
            Log.info("Click detected on magic thumb button (released)")
            let action = ConfigManager.shared.effectiveAction(for: .click)
            ActionDispatcher.shared.dispatch(action: action)
        }
        isTriggerEngaged = false
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(false)
        return true
    }

    public func handleButtonDown(buttonNumber: Int64) -> Bool {
        let config = ConfigManager.shared.activeConfig
        guard buttonNumber == config.triggerButtonIndex else { return false }
        isTriggerEngaged = true
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(true)

        if isCalibrationMode {
            onCalibrationEvent?(.triggerState(isDown: true, buttonIndex: Int(buttonNumber)))
        }

        // Safety watchdog: Automatically release if button-up is dropped or lost
        buttonSafetyTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.5)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTriggerEngaged else { return }
            Log.info("Trigger button safety watchdog expired. Resetting engagement.")
            self.reset()
        }
        timer.resume()
        self.buttonSafetyTimer = timer

        return config.swallowTriggerEvents
    }

    public func handleMouseDragged(deltaX: Double, deltaY: Double) -> Bool {
        guard isTriggerEngaged else { return false }
        let config = ConfigManager.shared.activeConfig
        accumulatedDeltaX += deltaX
        accumulatedDeltaY += deltaY
        let distance = hypot(accumulatedDeltaX, accumulatedDeltaY)

        if isCalibrationMode {
            onCalibrationEvent?(.motionUpdated(dx: accumulatedDeltaX, dy: accumulatedDeltaY, distance: distance))
            if distance >= config.thresholdDistance && !gestureConsumed {
                gestureConsumed = true
                magicGestureTimer?.cancel()
                magicGestureTimer = nil
                buttonSafetyTimer?.cancel()
                buttonSafetyTimer = nil
                let dir = resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY)
                let action = actionForDirection(dir)
                onCalibrationEvent?(.directionDetected(dir, action))
                onCalibrationEvent?(.gestureCompleted(wasClick: false, action))
                // Cleanly disengage motion tracking once calibration gesture is triggered
                isTriggerEngaged = false
                accumulatedDeltaX = 0.0
                accumulatedDeltaY = 0.0
                gestureConsumed = false
                onEngagementChanged?(false)
                onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: Int(config.triggerButtonIndex)))
            }
            return true
        }

        if distance < config.deadzoneRadius { return config.swallowTriggerEvents }
        if distance >= config.thresholdDistance && !gestureConsumed {
            gestureConsumed = true
            magicGestureTimer?.cancel()
            magicGestureTimer = nil
            buttonSafetyTimer?.cancel()
            buttonSafetyTimer = nil
            isTriggerEngaged = false
            onEngagementChanged?(false)
            executeDirectionalAction(resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY))
        }
        return config.swallowTriggerEvents
    }

    public func handleButtonUp(buttonNumber: Int64) -> Bool {
        let config = ConfigManager.shared.activeConfig
        guard buttonNumber == config.triggerButtonIndex else { return false }

        buttonSafetyTimer?.cancel()
        buttonSafetyTimer = nil

        if isCalibrationMode {
            let action: ActionDefinition?
            if !gestureConsumed {
                action = ConfigManager.shared.effectiveAction(for: .click)
                onCalibrationEvent?(.gestureCompleted(wasClick: true, action))
            } else {
                let dir = resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY)
                action = actionForDirection(dir)
                onCalibrationEvent?(.gestureCompleted(wasClick: false, action))
            }
            onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: Int(buttonNumber)))
            isTriggerEngaged = false
            accumulatedDeltaX = 0.0
            accumulatedDeltaY = 0.0
            gestureConsumed = false
            onEngagementChanged?(false)
            return true
        }

        if isTriggerEngaged && !gestureConsumed {
            Log.info("Click detected on trigger button (\(buttonNumber))")
            let action = ConfigManager.shared.effectiveAction(for: .click)
            ActionDispatcher.shared.dispatch(action: action)
        }
        isTriggerEngaged = false
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(false)
        return config.swallowTriggerEvents
    }

    private func resolveDirection(dx: Double, dy: Double) -> GestureDirection {
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func executeDirectionalAction(_ direction: GestureDirection) {
        switch direction {
        case .left:
            Log.info("Gesture: Drag Left")
            let action = ConfigManager.shared.effectiveAction(for: .dragLeft)
            ActionDispatcher.shared.dispatch(action: action)
        case .right:
            Log.info("Gesture: Drag Right")
            let action = ConfigManager.shared.effectiveAction(for: .dragRight)
            ActionDispatcher.shared.dispatch(action: action)
        case .up:
            Log.info("Gesture: Drag Up")
            let action = ConfigManager.shared.effectiveAction(for: .dragUp)
            ActionDispatcher.shared.dispatch(action: action)
        case .down:
            Log.info("Gesture: Drag Down")
            let action = ConfigManager.shared.effectiveAction(for: .dragDown)
            ActionDispatcher.shared.dispatch(action: action)
        }
    }

    public func actionForDirection(_ direction: GestureDirection) -> ActionDefinition? {
        switch direction {
        case .left: return ConfigManager.shared.effectiveAction(for: .dragLeft)
        case .right: return ConfigManager.shared.effectiveAction(for: .dragRight)
        case .up: return ConfigManager.shared.effectiveAction(for: .dragUp)
        case .down: return ConfigManager.shared.effectiveAction(for: .dragDown)
        }
    }
}
