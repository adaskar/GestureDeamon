import Foundation

/// High-performance stack-allocated curve peak filter to eliminate wheel tick jitter without heap allocations
public final class ScrollFilter {
    private var y0: Double = 0.0
    private var y1: Double = 0.0
    private var x0: Double = 0.0
    private var x1: Double = 0.0

    public init() {}

    @inline(__always)
    public func fill(with nextValue: (y: Double, x: Double)) -> (y: Double, x: Double) {
        let diffY = nextValue.y - y1
        y0 = y1
        y1 = y1 + 0.23 * diffY

        let diffX = nextValue.x - x1
        x0 = x1
        x1 = x1 + 0.23 * diffX

        return (y: y0, x: x0)
    }

    @inline(__always)
    public func value() -> (y: Double, x: Double) {
        return (y: y0, x: x0)
    }

    public func reset() {
        y0 = 0.0
        y1 = 0.0
        x0 = 0.0
        x1 = 0.0
    }
}
