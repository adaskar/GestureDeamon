import Foundation
import CoreGraphics

public enum GestureDirection { case left, right, up, down }

public final class GestureStateMachine {
    private var isTriggerEngaged = false
    private var accumulatedDeltaX: Double = 0.0
    private var accumulatedDeltaY: Double = 0.0
    private var gestureConsumed = false

    private var magicGestureTimer: DispatchSourceTimer?

    public var isEngaged: Bool { isTriggerEngaged }
    public var onEngagementChanged: ((Bool) -> Void)?

    public init() {}

    public func handleMagicDown(windowDurationMs: Double = 200.0) -> Bool {
        isTriggerEngaged = true
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        onEngagementChanged?(true)
        Log.info("Magic thumb button engaged (waiting for flick gesture or click timeout)...")

        magicGestureTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + (windowDurationMs / 1000.0))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isTriggerEngaged else { return }
            if !self.gestureConsumed {
                Log.info("Click detected on magic thumb button (stationary tap)")
                let config = ConfigManager.shared.activeConfig
                ActionDispatcher.shared.dispatch(action: config.clickAction)
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
        return config.swallowTriggerEvents
    }

    public func handleMouseDragged(deltaX: Double, deltaY: Double) -> Bool {
        guard isTriggerEngaged else { return false }
        let config = ConfigManager.shared.activeConfig
        accumulatedDeltaX += deltaX
        accumulatedDeltaY += deltaY
        let distance = hypot(accumulatedDeltaX, accumulatedDeltaY)
        if distance < config.deadzoneRadius { return config.swallowTriggerEvents }
        if distance >= config.thresholdDistance && !gestureConsumed {
            gestureConsumed = true
            magicGestureTimer?.cancel()
            magicGestureTimer = nil
            isTriggerEngaged = false
            onEngagementChanged?(false)
            executeDirectionalAction(resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY))
        }
        return config.swallowTriggerEvents
    }

    public func handleButtonUp(buttonNumber: Int64) -> Bool {
        let config = ConfigManager.shared.activeConfig
        guard buttonNumber == config.triggerButtonIndex else { return false }
        if isTriggerEngaged && !gestureConsumed {
            Log.info("Click detected on trigger button (\(buttonNumber))")
            ActionDispatcher.shared.dispatch(action: config.clickAction)
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
        let config = ConfigManager.shared.activeConfig
        switch direction {
        case .left:  Log.info("Gesture: Drag Left");  ActionDispatcher.shared.dispatch(action: config.dragLeftAction)
        case .right: Log.info("Gesture: Drag Right"); ActionDispatcher.shared.dispatch(action: config.dragRightAction)
        case .up:    Log.info("Gesture: Drag Up");    ActionDispatcher.shared.dispatch(action: config.dragUpAction)
        case .down:  Log.info("Gesture: Drag Down");  ActionDispatcher.shared.dispatch(action: config.dragDownAction)
        }
    }
}
