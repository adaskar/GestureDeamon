import Cocoa

public final class AccessibilityHelper {
    public static func verifyAccessibility(prompt: Bool = true) -> Bool {
        let checkOptionPromptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptionPromptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func pollForAccess(intervalSeconds: Double = 1.0, onGranted: @escaping () -> Void) {
        if verifyAccessibility(prompt: false) {
            onGranted()
            return
        }
        Log.info("Waiting for Accessibility permission grant...")
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler {
            if AXIsProcessTrustedWithOptions(nil) {
                Log.info("Accessibility permission granted.")
                timer.cancel()
                onGranted()
            }
        }
        timer.resume()
    }
}

