import Cocoa
import IOKit
import IOKit.hid

public final class PermissionHelper {
    public static var isAccessibilityGranted: Bool {
        return AXIsProcessTrustedWithOptions(nil)
    }

    public static var isInputMonitoringGranted: Bool {
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        return status == kIOHIDAccessTypeGranted
    }

    @discardableResult
    public static func requestAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static func verifyAndPrompt() {
        if !isAccessibilityGranted {
            Log.error("Accessibility permission missing. Requesting authorization...")
            _ = requestAccessibility()
        }
        if !isInputMonitoringGranted {
            Log.info("Input Monitoring permission missing (required for Direct Bluetooth LE HID++). Requesting authorization...")
            _ = requestInputMonitoring()
        }
    }

    public static func pollForAccess(intervalSeconds: Double = 1.0, onGranted: @escaping () -> Void) {
        if isAccessibilityGranted {
            onGranted()
            return
        }

        Log.info("Waiting for Accessibility permission grant...")
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler {
            if isAccessibilityGranted {
                Log.info("Accessibility permission granted.")
                timer.cancel()
                onGranted()
            }
        }
        timer.resume()
    }
}

