import Foundation

public enum Interpolator {
    /// Linear interpolation between current source and target destination
    public static func lerp(src: Double, dest: Double, trans: Double) -> Double {
        let diff = dest - src
        return diff * trans
    }

    /// 2nd-order smooth step easing
    public static func smoothStep2(src: Double, dest: Double) -> Double {
        guard dest != 0 else { return 0 }
        let x = (dest - src) / dest
        return x * x * (3.0 - 2.0 * x)
    }

    /// 3rd-order smooth step easing
    public static func smoothStep3(src: Double, dest: Double) -> Double {
        guard dest != 0 else { return 0 }
        let x = (dest - src) / dest
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }
}

