import Cocoa
import CoreGraphics
import os

public final class ScrollDispatchContext {
    public static let shared = ScrollDispatchContext()

    // Synthetic event marker to distinguish smoothed frames from raw hardware ticks
    public static let syntheticSmoothEventMarker: Int64 = 0x47455354534D54 // "GESTSMT" in ASCII hex

    public struct PostingSnapshot {
        public let event: CGEvent
        public let targetPID: pid_t
        public let generation: UInt64
        public let capturedAt: CFTimeInterval
    }

    private struct SnapshotState {
        var eventTemplate: CGEvent?
        var targetPID: pid_t = 0
        var generation: UInt64 = 0
        var updatedAt: CFTimeInterval = 0.0
    }

    private var state = SnapshotState()
    private var lock = os_unfair_lock_s()
    private let postQueue = DispatchQueue(label: "com.guru.GestureDaemon.scrollposter.post", qos: .userInteractive)
    private let eventTTL: CFTimeInterval = 5.0

    public init() {}

    public static func markSyntheticSmoothEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticSmoothEventMarker)
    }

    public static func isSyntheticSmoothEvent(_ event: CGEvent) -> Bool {
        return event.getIntegerValueField(.eventSourceUserData) == syntheticSmoothEventMarker
    }

    @discardableResult
    public func capture(event: CGEvent) -> Bool {
        guard let template = event.copy() else { return false }
        var pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid <= 1, let frontmost = NSWorkspace.shared.frontmostApplication {
            pid = frontmost.processIdentifier
        }

        os_unfair_lock_lock(&lock)
        state.eventTemplate = template
        state.targetPID = pid
        state.updatedAt = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&lock)
        return true
    }

    public func advanceGeneration() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    public func clearContext() {
        os_unfair_lock_lock(&lock)
        state.eventTemplate = nil
        state.targetPID = 0
        state.updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    public func invalidateAll() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        state.eventTemplate = nil
        state.targetPID = 0
        state.updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    public func preparePostingSnapshot() -> PostingSnapshot? {
        os_unfair_lock_lock(&lock)
        guard let eventClone = state.eventTemplate?.copy() else {
            os_unfair_lock_unlock(&lock)
            return nil
        }
        let snapshot = PostingSnapshot(
            event: eventClone,
            targetPID: state.targetPID,
            generation: state.generation,
            capturedAt: state.updatedAt
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    public func enqueue(_ snapshot: PostingSnapshot) {
        postQueue.async { [self] in
            os_unfair_lock_lock(&self.lock)
            let now = CFAbsoluteTimeGetCurrent()
            let validGeneration = (snapshot.generation == self.state.generation)
            let validTTL = (now - snapshot.capturedAt <= self.eventTTL)
            os_unfair_lock_unlock(&self.lock)

            guard validGeneration && validTTL else { return }

            if snapshot.targetPID > 0 {
                // Post directly to the destination process PID
                snapshot.event.postToPid(snapshot.targetPID)
            } else {
                // Fallback to HID event tap if target PID is unassigned
                snapshot.event.post(tap: .cghidEventTap)
            }
        }
    }
}

