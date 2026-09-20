import Cocoa
import CoreGraphics
import CoreVideo
import os

public final class ScrollPoster {
    public static let shared = ScrollPoster()

    private let filter = ScrollFilter()
    private var poster: CVDisplayLink?

    private var current = (y: 0.0, x: 0.0)
    private var delta = (y: 0.0, x: 0.0)
    private var buffer = (y: 0.0, x: 0.0)

    private var shifting = false
    private var durationTransition: Double = 0.088
    private var deadZone: Double = 1.0
    private var simulateTrackpad: Bool = true

    private var lastManualEventTime: CFTimeInterval = 0.0
    private var manualInputEnded = true
    private var momentumActive = false
    private var momentumEndScheduledTime: CFTimeInterval? = nil
    private var trackingEndScheduledTime: CFTimeInterval? = nil

    private let manualContinuationThreshold: CFTimeInterval = 0.18
    private let manualSeparationThreshold: CFTimeInterval = 0.45
    private let trackingEndAdvance: CFTimeInterval = 0.04
    private let momentumEndDelay: CFTimeInterval = 0.13

    private var stateLock = os_unfair_lock_s()
    private let dispatchContext = ScrollDispatchContext.shared

    private var keeper: Timer?
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0

    public var isAvailable: Bool {
        return poster != nil
    }

    public init() {}

    // MARK: - Update & Accumulation
    @discardableResult
    public func update(
        event: CGEvent,
        durationTransition: Double,
        y: Double,
        x: Double,
        speed: Double,
        deadZone: Double,
        simulateTrackpad: Bool,
        amplification: Double = 1.0
    ) -> ScrollPoster {
        guard dispatchContext.capture(event: event) else {
            return self
        }

        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }

        self.durationTransition = durationTransition
        self.deadZone = deadZone
        self.simulateTrackpad = simulateTrackpad

        // Direction preservation / accumulation
        if y * delta.y > 0 {
            buffer.y += y * speed * amplification
        } else {
            buffer.y = y * speed * amplification
            current.y = 0.0
        }

        if x * delta.x > 0 {
            buffer.x += x * speed * amplification
        } else {
            buffer.x = x * speed * amplification
            current.x = 0.0
        }
        delta = (y: y, x: x)

        let now = CFAbsoluteTimeGetCurrent()
        let interval = lastManualEventTime > 0.0 ? now - lastManualEventTime : nil
        let separatedByTime = interval == nil ? true : interval! >= manualSeparationThreshold
        let phase = ScrollPhaseTracker.shared.currentPhase
        let separatedPhase = (phase == .idle || phase == .leave || phase == .momentumEnd || phase == .trackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase

        let plan = ScrollPhaseTracker.shared.onManualInputDetected(isSeparated: separated)
        perform(plan, emitTargetImmediately: false)

        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil

        return self
    }

    public func updateShifting(enable: Bool) {
        os_unfair_lock_lock(&stateLock)
        shifting = enable
        os_unfair_lock_unlock(&stateLock)
    }

    private func shift(with nextValue: (y: Double, x: Double)) -> (y: Double, x: Double) {
        if shifting {
            // Shift transforms vertical wheel into horizontal wheel
            if nextValue.y != 0.0 && nextValue.x == 0.0 {
                return (y: 0.0, x: nextValue.y)
            } else {
                return (y: nextValue.y, x: nextValue.x)
            }
        }
        return (y: nextValue.y, x: nextValue.x)
    }

    /// Instant brake to stop any momentum/scrolling (e.g. on left mouse down)
    public func brake() {
        os_unfair_lock_lock(&stateLock)
        buffer = current
        perform(ScrollPhaseTracker.shared.onMomentumFinish(), emitTargetImmediately: true)
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        os_unfair_lock_unlock(&stateLock)
    }

    public func reset() {
        dispatchContext.invalidateAll()
        os_unfair_lock_lock(&stateLock)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

    private func resetUnlocked() {
        dispatchContext.clearContext()
        current = (y: 0.0, x: 0.0)
        delta = (y: 0.0, x: 0.0)
        buffer = (y: 0.0, x: 0.0)
        filter.reset()
        ScrollPhaseTracker.shared.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }

    // MARK: - CVDisplayLink Lifecycle
    public func create() {
        if let old = poster {
            if CVDisplayLinkIsRunning(old) {
                CVDisplayLinkStop(old)
            }
            poster = nil
        }

        var newPoster: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&newPoster)
        if result == kCVReturnSuccess, let validPoster = newPoster {
            CVDisplayLinkSetOutputCallback(validPoster, { (_, _, _, _, _, _) -> CVReturn in
                ScrollPoster.shared.processing()
                return kCVReturnSuccess
            }, nil)
            poster = validPoster
        } else {
            poster = nil
            Log.error("ScrollPoster: CVDisplayLink creation failed with code \(result)")
        }
    }

    public func tryStart() {
        guard let validPoster = poster else {
            if !recreateDisplayLink() {
                reset()
            }
            return
        }

        if !CVDisplayLinkIsRunning(validPoster) {
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            } else {
                _ = recreateDisplayLink()
            }
        }
    }

    public func stop(_ requestedPhase: ScrollLifecyclePhase = .momentumEnd) {
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
        }
        dispatchContext.advanceGeneration()

        os_unfair_lock_lock(&stateLock)
        let plan: ScrollPhaseTracker.TransitionPlan
        if requestedPhase == .momentumEnd {
            plan = ScrollPhaseTracker.shared.onMomentumFinish()
        } else {
            plan = ScrollPhaseTracker.shared.onManualInputEnded()
        }

        if simulateTrackpad {
            perform(plan, emitTargetImmediately: true)
        }

        manualInputEnded = true
        momentumActive = false
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

    @discardableResult
    private func recreateDisplayLink() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        create()
        if let validPoster = poster {
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            }
        }
        return true
    }

    public func startKeeper() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }

    public func stopKeeper() {
        keeper?.invalidate()
        keeper = nil
    }

    private func healthCheck() {
        guard let validPoster = poster else {
            recreateDisplayLink()
            return
        }
        if CVDisplayLinkIsRunning(validPoster) {
            os_unfair_lock_lock(&stateLock)
            let lastTime = lastCallbackTime
            os_unfair_lock_unlock(&stateLock)
            if lastTime > 0 && CFAbsoluteTimeGetCurrent() - lastTime > 2.0 {
                Log.info("ScrollPoster: zombie CVDisplayLink detected. Recreating...")
                recreateDisplayLink()
            }
        }
    }

    // MARK: - Frame Processing & Output Pump
    private func perform(_ plan: ScrollPhaseTracker.TransitionPlan, emitTargetImmediately: Bool, delta: (y: Double, x: Double) = (0.0, 0.0)) {
        if plan.queue.isEmpty && plan.target == nil {
            return
        }
        for item in plan.queue {
            emitPhase(item, delta: delta)
        }
        if let target = plan.target {
            if emitTargetImmediately {
                emitPhase(target, delta: delta)
            } else {
                ScrollPhaseTracker.shared.apply(phase: target.0, autoAdvance: target.1)
            }
        }
    }

    private func emitPhase(_ item: (ScrollLifecyclePhase, ScrollLifecyclePhase?), delta: (y: Double, x: Double)) {
        ScrollPhaseTracker.shared.apply(phase: item.0, autoAdvance: item.1)
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            ScrollPhaseTracker.shared.didDeliverFrame()
            return
        }
        let phaseOverride = simulateTrackpad ? phaseValues(for: item.0) : nil
        _ = post(snapshot, delta, phaseOverride: phaseOverride, fallbackToCurrentPhase: false)
    }

    private func processing() {
        var pendingStopPhase: ScrollLifecyclePhase?

        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = CFAbsoluteTimeGetCurrent()

        // Calculate smooth interpolation
        let frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: durationTransition),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: durationTransition)
        )

        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )

        let filledValue = filter.fill(with: frame)
        let shiftedValue = shift(with: filledValue)

        let now = CFAbsoluteTimeGetCurrent()
        if !manualInputEnded && lastManualEventTime > 0.0 && now - lastManualEventTime > manualContinuationThreshold {
            let endPlan = ScrollPhaseTracker.shared.onManualInputEnded()
            if !(endPlan.queue.isEmpty && endPlan.target == nil) {
                perform(endPlan, emitTargetImmediately: true)
            }
            manualInputEnded = true
            if trackingEndScheduledTime == nil {
                trackingEndScheduledTime = now + trackingEndAdvance
            }
        }

        let residualY = buffer.y - current.y
        let residualX = buffer.x - current.x
        let residualMagnitude = max(residualY.magnitude, residualX.magnitude)

        if manualInputEnded && residualMagnitude > deadZone {
            if !momentumActive {
                perform(ScrollPhaseTracker.shared.onMomentumStart(), emitTargetImmediately: false)
                momentumActive = true
            } else {
                perform(ScrollPhaseTracker.shared.onMomentumOngoing(), emitTargetImmediately: false)
            }
            momentumEndScheduledTime = nil
            trackingEndScheduledTime = nil
        } else if momentumActive && residualMagnitude <= deadZone {
            if momentumEndScheduledTime == nil {
                momentumEndScheduledTime = now + momentumEndDelay
            }
        } else {
            momentumEndScheduledTime = nil
            if momentumActive {
                momentumActive = false
            }
        }

        // Post output frame if exceeding deadZone threshold
        let outputMagnitude = max(abs(shiftedValue.y), abs(shiftedValue.x))
        if outputMagnitude > deadZone {
            _ = post(shiftedValue)
        }

        if let scheduled = momentumEndScheduledTime, momentumActive {
            if now >= scheduled {
                momentumEndScheduledTime = nil
                momentumActive = false
                pendingStopPhase = .momentumEnd
            }
        }

        if pendingStopPhase == nil && manualInputEnded && !momentumActive && residualMagnitude <= deadZone {
            let pendingStop = trackingEndScheduledTime != nil && now >= trackingEndScheduledTime!
            let outputSettled = outputMagnitude <= deadZone
            if pendingStop && outputSettled {
                trackingEndScheduledTime = nil
                pendingStopPhase = .trackingEnd
            }
        } else {
            trackingEndScheduledTime = nil
        }

        os_unfair_lock_unlock(&stateLock)

        if let phase = pendingStopPhase {
            stop(phase)
        }
    }

    private func phaseValues(for phase: ScrollLifecyclePhase) -> (scroll: Double, momentum: Double)? {
        guard let scrollVal = ScrollPhaseValueMapping[phase]?[.scroll],
              let momVal = ScrollPhaseValueMapping[phase]?[.momentum] else {
            return nil
        }
        return (scroll: scrollVal, momentum: momVal)
    }

    @discardableResult
    private func post(
        _ snapshot: ScrollDispatchContext.PostingSnapshot,
        _ v: (y: Double, x: Double),
        phaseOverride: (scroll: Double, momentum: Double)? = nil,
        fallbackToCurrentPhase: Bool = true
    ) -> Bool {
        if let override = phaseOverride {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: override.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: override.momentum)
        } else if fallbackToCurrentPhase, simulateTrackpad,
                  let currentVals = phaseValues(for: ScrollPhaseTracker.shared.currentPhase) {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: currentVals.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: currentVals.momentum)
        }

        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)
        snapshot.event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        ScrollDispatchContext.markSyntheticSmoothEvent(snapshot.event)

        dispatchContext.postDirectly(snapshot)
        ScrollPhaseTracker.shared.didDeliverFrame()
        return true
    }

    @discardableResult
    private func post(_ v: (y: Double, x: Double)) -> Bool {
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            return false
        }
        return post(snapshot, v)
    }
}

