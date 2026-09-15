import Cocoa
import Foundation

public enum ActionSlot {
    case click
    case dragLeft
    case dragRight
    case dragUp
    case dragDown
    case backButton
    case forwardButton
}

public struct ActionDefinition: Codable {
    public enum ActionType: String, Codable {
        case shortcut = "Shortcut"
        case application = "Application"
        case command = "Command"
    }
    public let type: ActionType
    public let keyCode: UInt16?
    public let modifiers: [String]?
    public let bundleIdentifier: String?
    public let commandPath: String?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case keyCode = "KeyCode"
        case modifiers = "Modifiers"
        case bundleIdentifier = "BundleIdentifier"
        case commandPath = "CommandPath"
    }
}

public struct AppProfile: Codable {
    public let clickAction: ActionDefinition?
    public let dragLeftAction: ActionDefinition?
    public let dragRightAction: ActionDefinition?
    public let dragUpAction: ActionDefinition?
    public let dragDownAction: ActionDefinition?
    public let backButtonAction: ActionDefinition?
    public let forwardButtonAction: ActionDefinition?

    enum CodingKeys: String, CodingKey {
        case clickAction = "ClickAction"
        case dragLeftAction = "DragLeftAction"
        case dragRightAction = "DragRightAction"
        case dragUpAction = "DragUpAction"
        case dragDownAction = "DragDownAction"
        case backButtonAction = "BackButtonAction"
        case forwardButtonAction = "ForwardButtonAction"
    }
}

public struct AppConfig: Codable {
    public let triggerButtonIndex: Int64
    public let thresholdDistance: Double
    public let deadzoneRadius: Double
    public let gestureWindowMs: Double?
    public let showMenuBarIcon: Bool?
    public let swallowTriggerEvents: Bool
    public let clickAction: ActionDefinition?
    public let dragLeftAction: ActionDefinition?
    public let dragRightAction: ActionDefinition?
    public let dragUpAction: ActionDefinition?
    public let dragDownAction: ActionDefinition?

    // Side Navigation Buttons (Back / Forward)
    public let enableSideButtons: Bool?
    public let backButtonIndex: Int64?
    public let forwardButtonIndex: Int64?
    public let backButtonAction: ActionDefinition?
    public let forwardButtonAction: ActionDefinition?

    // Per-Application Contextual Profiles
    public let applications: [String: AppProfile]?

    enum CodingKeys: String, CodingKey {
        case triggerButtonIndex = "TriggerButtonIndex"
        case thresholdDistance = "ThresholdDistance"
        case deadzoneRadius = "DeadzoneRadius"
        case gestureWindowMs = "GestureWindowMs"
        case showMenuBarIcon = "ShowMenuBarIcon"
        case swallowTriggerEvents = "SwallowTriggerEvents"
        case clickAction = "ClickAction"
        case dragLeftAction = "DragLeftAction"
        case dragRightAction = "DragRightAction"
        case dragUpAction = "DragUpAction"
        case dragDownAction = "DragDownAction"
        case enableSideButtons = "EnableSideButtons"
        case backButtonIndex = "BackButtonIndex"
        case forwardButtonIndex = "ForwardButtonIndex"
        case backButtonAction = "BackButtonAction"
        case forwardButtonAction = "ForwardButtonAction"
        case applications = "Applications"
    }
}

public final class ConfigManager {
    public static let shared = ConfigManager()
    public private(set) var activeConfig: AppConfig

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default

    private var configURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let primaryPath = home.appendingPathComponent(".config/GestureDaemon/config.plist")
        let fallbackPath = home.appendingPathComponent("Library/Application Support/GestureDaemon/config.plist")
        if fileManager.fileExists(atPath: primaryPath.path) { return primaryPath }
        if fileManager.fileExists(atPath: fallbackPath.path) { return fallbackPath }
        return primaryPath
    }

    private init() {
        self.activeConfig = ConfigManager.fallbackDefaultConfig()
        loadConfiguration()
        startMonitoringConfigFile()
    }

    public func effectiveAction(for slot: ActionSlot) -> ActionDefinition? {
        let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let bundle = currentBundle {
            var profile = activeConfig.applications?[bundle]
            if profile == nil && bundle.hasPrefix("com.microsoft.VSCode") {
                profile = activeConfig.applications?["com.microsoft.VSCode"]
            }
            if profile == nil && (bundle == "com.visualstudio.code.oss" || bundle == "com.vscodium") {
                profile = activeConfig.applications?["com.microsoft.VSCode"]
            }

            if let matchedProfile = profile {
                switch slot {
                case .click:
                    if let action = matchedProfile.clickAction { return action }
                case .dragLeft:
                    if let action = matchedProfile.dragLeftAction { return action }
                case .dragRight:
                    if let action = matchedProfile.dragRightAction { return action }
                case .dragUp:
                    if let action = matchedProfile.dragUpAction { return action }
                case .dragDown:
                    if let action = matchedProfile.dragDownAction { return action }
                case .backButton:
                    if let action = matchedProfile.backButtonAction { return action }
                case .forwardButton:
                    if let action = matchedProfile.forwardButtonAction { return action }
                }
            }
        }

        // Fallback to global config
        switch slot {
        case .click:
            return activeConfig.clickAction
        case .dragLeft:
            return activeConfig.dragLeftAction
        case .dragRight:
            return activeConfig.dragRightAction
        case .dragUp:
            return activeConfig.dragUpAction
        case .dragDown:
            return activeConfig.dragDownAction
        case .backButton:
            return activeConfig.backButtonAction
        case .forwardButton:
            return activeConfig.forwardButtonAction
        }
    }

    public func loadConfiguration() {
        let url = configURL
        guard fileManager.fileExists(atPath: url.path) else {
            Log.info("No config.plist found at \(url.path). Writing default template.")
            writeDefaultConfig(to: url)
            return
        }
        do {
            let data = try Data(contentsOf: url)
            self.activeConfig = try PropertyListDecoder().decode(AppConfig.self, from: data)
            Log.info("Configuration loaded from: \(url.path)")
        } catch {
            Log.error("Failed to parse config.plist: \(error.localizedDescription). Keeping active settings.")
        }
    }

    public func updateShowMenuBarIcon(_ show: Bool) {
        let url = configURL
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            dict = existing
        }
        dict["ShowMenuBarIcon"] = show
        if let outputData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
            try? outputData.write(to: url, options: .atomic)
            loadConfiguration()
        }
    }

    private func startMonitoringConfigFile() {
        let path = configURL.path
        let fd = open(path, O_EVTONLY)
        guard fd != -1 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.delete, .write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            Log.info("config.plist changed. Reloading...")
            self?.loadConfiguration()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.fileMonitorSource = source
    }

    private func writeDefaultConfig(to url: URL) {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try encoder.encode(self.activeConfig).write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            Log.info("Default config written to \(url.path) (permissions locked to 600)")
        } catch {
            Log.error("Failed to write default config: \(error)")
        }
    }

    private static func fallbackDefaultConfig() -> AppConfig {
        AppConfig(
            triggerButtonIndex: 5, thresholdDistance: 35.0, deadzoneRadius: 8.0,
            gestureWindowMs: 200.0, showMenuBarIcon: true, swallowTriggerEvents: true,
            clickAction: ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragLeftAction: ActionDefinition(type: .shortcut, keyCode: 124, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragRightAction: ActionDefinition(type: .shortcut, keyCode: 123, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragUpAction: ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragDownAction: ActionDefinition(type: .shortcut, keyCode: 125, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            enableSideButtons: true,
            backButtonIndex: 3,
            forwardButtonIndex: 4,
            backButtonAction: nil,
            forwardButtonAction: nil,
            applications: nil
        )
    }
}
