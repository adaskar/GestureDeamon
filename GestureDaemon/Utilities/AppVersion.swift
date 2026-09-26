import Foundation

/// Centralized single source of truth for GestureDaemon application version and build metadata.
public enum AppVersion {
    public static let current = "1.0.1"
    public static let build = "4"

    /// Resolved semantic version string.
    /// Prefers CFBundleShortVersionString from Info.plist if available, falling back to static constant.
    public static var versionString: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? current
    }

    /// Resolved build number string.
    /// Prefers CFBundleVersion from Info.plist if available, falling back to static constant.
    public static var buildString: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? build
    }

    /// Full display version (e.g., "1.0.1 (build 4)")
    public static var fullDisplayString: String {
        return "v\(versionString) (build \(buildString))"
    }
}
