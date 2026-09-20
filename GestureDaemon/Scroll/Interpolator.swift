import Foundation

public enum Interpolator {
    /// Linear interpolation: returns the per-frame step to move `src` toward `dest`.
    /// `trans` is the normalized transition coefficient in (0, 1) — derived from `durationTransition`.
    public static func lerp(src: Double, dest: Double, trans: Double) -> Double {
        return (dest - src) * trans
    }
}

