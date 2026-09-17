import Foundation
import CoreGraphics

public enum GestureDirection { case left, right, up, down }

public enum CalibrationEvent {
    case triggerState(isDown: Bool, buttonIndex: Int)
    case motionUpdated(dx: Double, dy: Double, distance: Double)
    case directionDetected(GestureDirection?, ActionDefinition?)
    case gestureCompleted(wasClick: Bool, ActionDefinition?)
    case scrollChording(isUp: Bool, action: ActionDefinition?)
    case otherButton(buttonIndex: Int, isDown: Bool, actionName: String?)
}

public final class GestureStateMachine {
    private var isTriggerEngaged = false
    private var accumulatedDeltaX: Double = 0.0
    private var accumulatedDeltaY: Double = 0.0
    private var gestureConsumed = false

    private var cachedThresholdDistance: Double = 35.0
    private var cachedDeadzoneRadius: Double = 8.0
    private var cachedSwallowTriggerEvents: Bool = true

    private var magicGestureTimer: DispatchSourceTimer?
    private var buttonSafetyTimer: DispatchSourceTimer?

    public var isEngaged: Bool { isTriggerEngaged }
    public var onEngagementChanged: ((Bool) -> Void)?

    // Live Calibration Mode (for Preferences window Live Tester)
    public var isCalibrationMode: Bool = false
    public var onCalibrationEvent: ((CalibrationEvent) -> Void)?

    public init() {}

    private func updateCachedPhysics() {
        let config = ConfigManager.shared.activeConfig
        self.cachedThresholdDistance = config.thresholdDistance
        self.cachedDeadzoneRadius = config.deadzoneRadius
        self.cachedSwallowTriggerEvents = config.swallowTriggerEvents
    }

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

    public func handleMagicDown(isMacro: Bool = false, windowDurationMs: Double = 200.0) -> Bool {
        updateCachedPhysics()
        isTriggerEngaged = true
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(true)
        Log.info("Magic thumb button engaged (waiting for flick gesture or click timeout)...")

        let triggerIndex = Int(ConfigManager.shared.activeConfig.triggerButtonIndex)

        if isCalibrationMode {
            onCalibrationEvent?(.triggerState(isDown: true, buttonIndex: triggerIndex))
            return true
        }

        magicGestureTimer?.cancel()
        if isMacro {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + (windowDurationMs / 1000.0))
            timer.setEventHandler { [weak self] in
                guard let self = self, self.isTriggerEngaged else { return }
                if !self.gestureConsumed {
                    Log.info("Click detected on magic thumb button macro (stationary tap)")
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
        } else {
            // For physical HID++ button, we have physical release via handleMagicUp().
            // Keep a generous safety watchdog (5.0s) only to prevent stuck state if a Bluetooth packet is lost.
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 5.0)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.isTriggerEngaged else { return }
                Log.info("Physical trigger safety watchdog expired. Resetting engagement.")
                self.reset()
            }
            timer.resume()
            self.magicGestureTimer = timer
        }
        return true
    }

    public func handleMagicUp() -> Bool {
        let triggerIndex = Int(ConfigManager.shared.activeConfig.triggerButtonIndex)

        guard isTriggerEngaged else {
            if isCalibrationMode {
                onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: triggerIndex))
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
            onCalibrationEvent?(.triggerState(isDown: false, buttonIndex: triggerIndex))
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
        updateCachedPhysics()
        isTriggerEngaged = true
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(true)

        if isCalibrationMode {
            onCalibrationEvent?(.triggerState(isDown: true, buttonIndex: Int(buttonNumber)))
            return true
        }

        // Safety watchdog: Automatically release if button-up is dropped or lost
        buttonSafetyTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTriggerEngaged else { return }
            Log.info("Trigger button safety watchdog expired. Resetting engagement.")
            self.reset()
        }
        timer.resume()
        self.buttonSafetyTimer = timer

        return cachedSwallowTriggerEvents
    }

    public func handleMouseDragged(deltaX: Double, deltaY: Double) -> Bool {
        guard isTriggerEngaged else { return false }
        accumulatedDeltaX += deltaX
        accumulatedDeltaY += deltaY
        let distance = hypot(accumulatedDeltaX, accumulatedDeltaY)

        if isCalibrationMode {
            onCalibrationEvent?(.motionUpdated(dx: accumulatedDeltaX, dy: accumulatedDeltaY, distance: distance))
            if distance >= cachedThresholdDistance {
                gestureConsumed = true
                let dir = resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY)
                let action = actionForDirection(dir)
                onCalibrationEvent?(.directionDetected(dir, action))
            } else {
                onCalibrationEvent?(.directionDetected(nil, nil))
            }
            return true
        }

        if distance < cachedDeadzoneRadius { return cachedSwallowTriggerEvents }
        if distance >= cachedThresholdDistance && !gestureConsumed {
            gestureConsumed = true
            magicGestureTimer?.cancel()
            magicGestureTimer = nil
            buttonSafetyTimer?.cancel()
            buttonSafetyTimer = nil
            isTriggerEngaged = false
            onEngagementChanged?(false)
            executeDirectionalAction(resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY))
        }
        return cachedSwallowTriggerEvents
    }

    public func handleScrollWheel(deltaY: Int64) -> Bool {
        guard isTriggerEngaged else { return false }
        gestureConsumed = true
        // Damp accumulated motion to prevent accidental directional gesture while scrolling
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0

        // Extend safety timers while actively scrolling
        magicGestureTimer?.schedule(deadline: .now() + 5.0)
        buttonSafetyTimer?.schedule(deadline: .now() + 5.0)

        // Inverted to match physical wheel roll direction
        let slot: ActionSlot = deltaY < 0 ? .scrollUp : .scrollDown
        let action = ConfigManager.shared.effectiveAction(for: slot)

        if isCalibrationMode {
            onCalibrationEvent?(.scrollChording(isUp: slot == .scrollUp, action: action))
            return true
        }

        ActionDispatcher.shared.dispatch(action: action)
        return true
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
        return cachedSwallowTriggerEvents
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
