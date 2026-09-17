import Cocoa
import Foundation

public enum ActionSlot: String, CaseIterable, Identifiable {
    case click = "Thumb Click"
    case dragLeft = "Swipe Left"
    case dragRight = "Swipe Right"
    case dragUp = "Swipe Up"
    case dragDown = "Swipe Down"
    case backButton = "Back Button"
    case forwardButton = "Forward Button"

    public var id: String { rawValue }
}

public struct ActionDefinition: Codable, Equatable, Hashable {
    public enum ActionType: String, Codable, CaseIterable, Identifiable {
        case shortcut = "Shortcut"
        case application = "Application"
        case command = "Command"

        public var id: String { rawValue }
    }

    public var type: ActionType
    public var keyCode: UInt16?
    public var modifiers: [String]?
    public var bundleIdentifier: String?
    public var commandPath: String?
    public var comment: String?

    public init(
        type: ActionType,
        keyCode: UInt16? = nil,
        modifiers: [String]? = nil,
        bundleIdentifier: String? = nil,
        commandPath: String? = nil,
        comment: String? = nil
    ) {
        self.type = type
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.bundleIdentifier = bundleIdentifier
        self.commandPath = commandPath
        self.comment = comment
    }

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case keyCode = "KeyCode"
        case modifiers = "Modifiers"
        case bundleIdentifier = "BundleIdentifier"
        case commandPath = "CommandPath"
        case comment = "Comment"
    }
}

public struct AppProfile: Codable, Equatable, Hashable {
    public var clickAction: ActionDefinition?
    public var dragLeftAction: ActionDefinition?
    public var dragRightAction: ActionDefinition?
    public var dragUpAction: ActionDefinition?
    public var dragDownAction: ActionDefinition?
    public var backButtonAction: ActionDefinition?
    public var forwardButtonAction: ActionDefinition?

    public init(
        clickAction: ActionDefinition? = nil,
        dragLeftAction: ActionDefinition? = nil,
        dragRightAction: ActionDefinition? = nil,
        dragUpAction: ActionDefinition? = nil,
        dragDownAction: ActionDefinition? = nil,
        backButtonAction: ActionDefinition? = nil,
        forwardButtonAction: ActionDefinition? = nil
    ) {
        self.clickAction = clickAction
        self.dragLeftAction = dragLeftAction
        self.dragRightAction = dragRightAction
        self.dragUpAction = dragUpAction
        self.dragDownAction = dragDownAction
        self.backButtonAction = backButtonAction
        self.forwardButtonAction = forwardButtonAction
    }

    enum CodingKeys: String, CodingKey {
        case clickAction = "ClickAction"
        case dragLeftAction = "DragLeftAction"
        case dragRightAction = "DragRightAction"
        case dragUpAction = "DragUpAction"
        case dragDownAction = "DragDownAction"
        case backButtonAction = "BackButtonAction"
        case forwardButtonAction = "ForwardButtonAction"
    }

    public func action(for slot: ActionSlot) -> ActionDefinition? {
        switch slot {
        case .click: return clickAction
        case .dragLeft: return dragLeftAction
        case .dragRight: return dragRightAction
        case .dragUp: return dragUpAction
        case .dragDown: return dragDownAction
        case .backButton: return backButtonAction
        case .forwardButton: return forwardButtonAction
        }
    }

    public mutating func setAction(_ action: ActionDefinition?, for slot: ActionSlot) {
        switch slot {
        case .click: clickAction = action
        case .dragLeft: dragLeftAction = action
        case .dragRight: dragRightAction = action
        case .dragUp: dragUpAction = action
        case .dragDown: dragDownAction = action
        case .backButton: backButtonAction = action
        case .forwardButton: forwardButtonAction = action
        }
    }
}

public struct AppConfig: Codable, Equatable {
    public var triggerButtonIndex: Int64
    public var thresholdDistance: Double
    public var deadzoneRadius: Double
    public var gestureWindowMs: Double?
    public var showMenuBarIcon: Bool?
    public var swallowTriggerEvents: Bool
    public var clickAction: ActionDefinition?
    public var dragLeftAction: ActionDefinition?
    public var dragRightAction: ActionDefinition?
    public var dragUpAction: ActionDefinition?
    public var dragDownAction: ActionDefinition?

    // Side Navigation Buttons (Back / Forward)
    public var enableSideButtons: Bool?
    public var backButtonIndex: Int64?
    public var forwardButtonIndex: Int64?
    public var backButtonAction: ActionDefinition?
    public var forwardButtonAction: ActionDefinition?

    // Logging Configuration
    public var enableLogging: Bool?
    public var logLevel: String?

    // Per-Application Contextual Profiles
    public var applications: [String: AppProfile]?

    public init(
        triggerButtonIndex: Int64 = 5,
        thresholdDistance: Double = 35.0,
        deadzoneRadius: Double = 8.0,
        gestureWindowMs: Double? = 75.0,
        showMenuBarIcon: Bool? = true,
        swallowTriggerEvents: Bool = true,
        clickAction: ActionDefinition? = nil,
        dragLeftAction: ActionDefinition? = nil,
        dragRightAction: ActionDefinition? = nil,
        dragUpAction: ActionDefinition? = nil,
        dragDownAction: ActionDefinition? = nil,
        enableSideButtons: Bool? = true,
        backButtonIndex: Int64? = 3,
        forwardButtonIndex: Int64? = 4,
        backButtonAction: ActionDefinition? = nil,
        forwardButtonAction: ActionDefinition? = nil,
        enableLogging: Bool? = false,
        logLevel: String? = "Info",
        applications: [String: AppProfile]? = nil
    ) {
        self.triggerButtonIndex = triggerButtonIndex
        self.thresholdDistance = thresholdDistance
        self.deadzoneRadius = deadzoneRadius
        self.gestureWindowMs = gestureWindowMs
        self.showMenuBarIcon = showMenuBarIcon
        self.swallowTriggerEvents = swallowTriggerEvents
        self.clickAction = clickAction
        self.dragLeftAction = dragLeftAction
        self.dragRightAction = dragRightAction
        self.dragUpAction = dragUpAction
        self.dragDownAction = dragDownAction
        self.enableSideButtons = enableSideButtons
        self.backButtonIndex = backButtonIndex
        self.forwardButtonIndex = forwardButtonIndex
        self.backButtonAction = backButtonAction
        self.forwardButtonAction = forwardButtonAction
        self.enableLogging = enableLogging
        self.logLevel = logLevel
        self.applications = applications
    }

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
        case enableLogging = "EnableLogging"
        case logLevel = "LogLevel"
        case applications = "Applications"
    }

    public func globalAction(for slot: ActionSlot) -> ActionDefinition? {
        switch slot {
        case .click: return clickAction
        case .dragLeft: return dragLeftAction
        case .dragRight: return dragRightAction
        case .dragUp: return dragUpAction
        case .dragDown: return dragDownAction
        case .backButton: return backButtonAction
        case .forwardButton: return forwardButtonAction
        }
    }

    public mutating func setGlobalAction(_ action: ActionDefinition?, for slot: ActionSlot) {
        switch slot {
        case .click: clickAction = action
        case .dragLeft: dragLeftAction = action
        case .dragRight: dragRightAction = action
        case .dragUp: dragUpAction = action
        case .dragDown: dragDownAction = action
        case .backButton: backButtonAction = action
        case .forwardButton: forwardButtonAction = action
        }
    }
}

public final class ConfigManager {
    public static let shared = ConfigManager()
    public static let configDidChangeNotification = Notification.Name("GestureDaemon.configDidChangeNotification")

    public private(set) var activeConfig: AppConfig {
        didSet {
            updateOverriddenSlots()
        }
    }
    private var overriddenSlots: Set<ActionSlot> = []

    private func updateOverriddenSlots() {
        var slots = Set<ActionSlot>()
        if let apps = activeConfig.applications {
            for profile in apps.values {
                for slot in ActionSlot.allCases {
                    if profile.action(for: slot) != nil {
                        slots.insert(slot)
                    }
                }
            }
        }
        self.overriddenSlots = slots
    }

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default

    public var configURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let primaryPath = home.appendingPathComponent(".config/GestureDaemon/config.plist")
        let fallbackPath = home.appendingPathComponent("Library/Application Support/GestureDaemon/config.plist")
        if fileManager.fileExists(atPath: primaryPath.path) { return primaryPath }
        if fileManager.fileExists(atPath: fallbackPath.path) { return fallbackPath }
        return primaryPath
    }

    private init() {
        self.activeConfig = ConfigManager.fallbackDefaultConfig()
        updateOverriddenSlots()
        Log.isEnabled = self.activeConfig.enableLogging ?? false
        Log.currentLevel = LogLevel.fromString(self.activeConfig.logLevel)
        loadConfiguration()
        startMonitoringConfigFile()
    }

    public func effectiveAction(for slot: ActionSlot) -> ActionDefinition? {
        // Fast-path: If no application profile overrides this slot, return the global action
        // immediately in O(1) time without querying NSWorkspace (zero IPC, zero latency, zero CPU on app switch).
        guard overriddenSlots.contains(slot), let apps = activeConfig.applications else {
            return activeConfig.globalAction(for: slot)
        }

        let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let bundle = currentBundle {
            // 1. Exact match against configured bundle identifier
            var profile = apps[bundle]

            // 2. Dynamic prefix match (e.g. configured "com.microsoft.VSCode" matches "com.microsoft.VSCode.Insiders")
            if profile == nil {
                for (pattern, configuredProfile) in apps {
                    if bundle.hasPrefix(pattern) {
                        profile = configuredProfile
                        break
                    }
                }
            }

            if let matchedProfile = profile {
                if let action = matchedProfile.action(for: slot) {
                    return action
                }
            }
        }

        // Fallback to global config
        return activeConfig.globalAction(for: slot)
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
            Log.isEnabled = self.activeConfig.enableLogging ?? false
            Log.currentLevel = LogLevel.fromString(self.activeConfig.logLevel)
            Log.info("Configuration loaded from: \(url.path)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                NotificationCenter.default.post(name: ConfigManager.configDidChangeNotification, object: self.activeConfig)
            }
        } catch {
            Log.error("Failed to parse config.plist: \(error.localizedDescription). Keeping active settings.")
        }
    }

    public func saveConfiguration(_ newConfig: AppConfig) throws {
        let url = configURL
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(newConfig)

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        self.activeConfig = newConfig
        Log.isEnabled = newConfig.enableLogging ?? false
        Log.currentLevel = LogLevel.fromString(newConfig.logLevel)
        Log.info("Configuration successfully saved to: \(url.path)")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ConfigManager.configDidChangeNotification, object: newConfig)
        }
    }

    public func resetToDefaults() {
        let def = ConfigManager.fallbackDefaultConfig()
        do {
            try saveConfiguration(def)
            Log.info("Configuration reset to factory defaults.")
        } catch {
            Log.error("Failed to reset configuration to defaults: \(error.localizedDescription)")
        }
    }

    public func updateShowMenuBarIcon(_ show: Bool) {
        var updated = activeConfig
        updated.showMenuBarIcon = show
        try? saveConfiguration(updated)
    }

    private func startMonitoringConfigFile() {
        let path = configURL.path
        let fd = open(path, O_EVTONLY)
        guard fd != -1 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.delete, .write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            Log.info("config.plist changed externally. Reloading...")
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

    public static func fallbackDefaultConfig() -> AppConfig {
        AppConfig(
            triggerButtonIndex: 5, thresholdDistance: 35.0, deadzoneRadius: 8.0,
            gestureWindowMs: 75.0, showMenuBarIcon: true, swallowTriggerEvents: true,
            clickAction: ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"], comment: "Mission Control (Ctrl+Up)"),
            dragLeftAction: ActionDefinition(type: .shortcut, keyCode: 124, modifiers: ["Control"], comment: "Natural swipe left -> Switch to Right Space"),
            dragRightAction: ActionDefinition(type: .shortcut, keyCode: 123, modifiers: ["Control"], comment: "Natural swipe right -> Switch to Left Space"),
            dragUpAction: ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"], comment: "Mission Control (Ctrl+Up)"),
            dragDownAction: ActionDefinition(type: .shortcut, keyCode: 125, modifiers: ["Control"], comment: "App Exposé (Ctrl+Down)"),
            enableSideButtons: true,
            backButtonIndex: 3,
            forwardButtonIndex: 4,
            backButtonAction: nil,
            forwardButtonAction: nil,
            enableLogging: false,
            logLevel: "Info",
            applications: [
                "com.microsoft.VSCode": AppProfile(
                    clickAction: nil,
                    dragLeftAction: nil,
                    dragRightAction: nil,
                    dragUpAction: nil,
                    dragDownAction: nil,
                    backButtonAction: ActionDefinition(type: .shortcut, keyCode: 24, modifiers: ["Control"], comment: "VS Code Navigate Back (Ctrl+-)"),
                    forwardButtonAction: ActionDefinition(type: .shortcut, keyCode: 24, modifiers: ["Control", "Shift"], comment: "VS Code Navigate Forward (Ctrl+Shift+-)")
                )
            ]
        )
    }
}
