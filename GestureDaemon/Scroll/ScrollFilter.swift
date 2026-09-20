import Foundation

/// Non-linear curve peak filter to eliminate initial wheel tick jitter and produce smooth acceleration
public final class ScrollFilter {
    private var curveWindowY = [0.0, 0.0]
    private var curveWindowX = [0.0, 0.0]

    public init() {}

    public func fill(with nextValue: (y: Double, x: Double)) -> (y: Double, x: Double) {
        curveWindowY = polish(curveWindowY, with: nextValue.y)
        curveWindowX = polish(curveWindowX, with: nextValue.x)
        return value()
    }

    public func value() -> (y: Double, x: Double) {
        return (y: curveWindowY[0], x: curveWindowX[0])
    }

    public func reset() {
        curveWindowY = [0.0, 0.0]
        curveWindowX = [0.0, 0.0]
    }

    private func polish(_ array: [Double], with nextValue: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first + 0.23 * diff, first + 0.50 * diff, first + 0.77 * diff, nextValue]
    }
}

