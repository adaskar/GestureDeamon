import Foundation
import ServiceManagement

public final class LoginItemManager {
    public static let shared = LoginItemManager()

    private init() {}

    public var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    public func setLaunchAtLogin(enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                        Log.info("Registered app with SMAppService (Launch at Login enabled).")
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        Log.info("Unregistered app from SMAppService (Launch at Login disabled).")
                    }
                }
                return true
            } catch {
                Log.error("Failed to update Launch at Login state: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }

    public var statusDescription: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return "Enabled"
            case .notRegistered: return "Not Registered"
            case .requiresApproval: return "Requires User Approval in System Settings"
            case .notFound: return "App Service Not Found"
            @unknown default: return "Unknown"
            }
        }
        return "Not supported on this macOS version"
    }
}

