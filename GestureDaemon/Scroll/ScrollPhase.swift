import Foundation

public enum ScrollLifecyclePhase: Equatable {
    case idle
    case hold
    case trackingBegin
    case trackingOngoing
    case trackingEnd
    case momentumBegin
    case momentumOngoing
    case momentumEnd
    case leave
}

public enum PhaseDimension {
    case scroll
    case momentum
}

public let ScrollPhaseValueMapping: [ScrollLifecyclePhase: [PhaseDimension: Double]] = [
    .idle: [.scroll: 0.0, .momentum: 0.0],
    .hold: [.scroll: 128.0, .momentum: 0.0],
    .trackingBegin: [.scroll: 1.0, .momentum: 0.0],
    .trackingOngoing: [.scroll: 2.0, .momentum: 0.0],
    .trackingEnd: [.scroll: 4.0, .momentum: 0.0],
    .momentumBegin: [.scroll: 0.0, .momentum: 1.0],
    .momentumOngoing: [.scroll: 0.0, .momentum: 2.0],
    .momentumEnd: [.scroll: 0.0, .momentum: 3.0],
    .leave: [.scroll: 8.0, .momentum: 0.0]
]

/// Tracks the macOS trackpad-phase lifecycle (scroll begin / ongoing / momentum / end).
///
/// **Thread safety**: `ScrollPhaseTracker` has no internal lock. All mutations (`apply`, `didDeliverFrame`,
/// `reset`, and all `on*` query methods) MUST be called while holding `ScrollPoster.stateLock`.
/// This is intentional: the poster is the sole owner of phase transitions, so adding a second lock
/// would introduce redundant contention with no benefit.
public final class ScrollPhaseTracker {
    public static let shared = ScrollPhaseTracker()

    public private(set) var currentPhase: ScrollLifecyclePhase = .idle
    private var pendingPhaseAfterDelivery: ScrollLifecyclePhase? = nil

    public struct TransitionPlan {
        public let queue: [(ScrollLifecyclePhase, ScrollLifecyclePhase?)]
        public let target: (ScrollLifecyclePhase, ScrollLifecyclePhase?)?

        public init(
            queue: [(ScrollLifecyclePhase, ScrollLifecyclePhase?)] = [],
            target: (ScrollLifecyclePhase, ScrollLifecyclePhase?)? = nil
        ) {
            self.queue = queue
            self.target = target
        }
    }

    public init() {}

    public func reset() {
        currentPhase = .idle
        pendingPhaseAfterDelivery = nil
    }

    public func apply(phase: ScrollLifecyclePhase, autoAdvance: ScrollLifecyclePhase? = nil) {
        currentPhase = phase
        pendingPhaseAfterDelivery = autoAdvance
    }

    public func didDeliverFrame() {
        if let next = pendingPhaseAfterDelivery {
            currentPhase = next
            pendingPhaseAfterDelivery = nil
        }
    }

    public func onManualInputDetected(isSeparated: Bool) -> TransitionPlan {
        if currentPhase == .momentumBegin || currentPhase == .momentumOngoing {
            if isSeparated {
                return TransitionPlan(
                    queue: [(.momentumEnd, .idle), (.trackingBegin, .trackingOngoing)]
                )
            } else {
                return TransitionPlan(
                    queue: [(.momentumEnd, .idle)],
                    target: (.trackingBegin, .trackingOngoing)
                )
            }
        }
        if isSeparated {
            return TransitionPlan(queue: [(.trackingBegin, .trackingOngoing)])
        }
        if currentPhase == .trackingBegin || currentPhase == .trackingOngoing {
            return TransitionPlan(target: (.trackingOngoing, nil))
        }
        return TransitionPlan(target: (.trackingBegin, .trackingOngoing))
    }

    public func onManualInputEnded() -> TransitionPlan {
        switch currentPhase {
        case .trackingBegin, .trackingOngoing:
            return TransitionPlan(target: (.trackingEnd, nil))
        default:
            return TransitionPlan()
        }
    }

    public func onMomentumStart() -> TransitionPlan {
        switch currentPhase {
        case .trackingEnd, .momentumEnd:
            return TransitionPlan(target: (.momentumBegin, .momentumOngoing))
        case .momentumBegin:
            return TransitionPlan(target: (.momentumOngoing, nil))
        default:
            return TransitionPlan()
        }
    }

    public func onMomentumOngoing() -> TransitionPlan {
        switch currentPhase {
        case .momentumBegin:
            return TransitionPlan(target: (.momentumOngoing, nil))
        default:
            return TransitionPlan()
        }
    }

    public func onMomentumFinish() -> TransitionPlan {
        switch currentPhase {
        case .momentumBegin, .momentumOngoing:
            return TransitionPlan(target: (.momentumEnd, .idle))
        case .trackingBegin, .trackingOngoing, .trackingEnd:
            return TransitionPlan(target: (.trackingEnd, .idle))
        default:
            return TransitionPlan()
        }
    }
}

