import Cocoa

public final class AccessibilityHelper {
    public static func verifyAccessibility(prompt: Bool = true) -> Bool {
        if prompt {
            return PermissionHelper.requestAccessibility()
        } else {
            return PermissionHelper.isAccessibilityGranted
        }
    }

    public static func pollForAccess(intervalSeconds: Double = 1.0, onGranted: @escaping () -> Void) {
        PermissionHelper.pollForAccess(intervalSeconds: intervalSeconds, onGranted: onGranted)
    }
}
