import Cocoa

public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var isPaused = false

    private override init() {
        super.init()
    }

    public func setup() {
        guard ConfigManager.shared.activeConfig.showMenuBarIcon ?? true else {
            Log.info("Menu bar icon disabled by configuration.")
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "GestureDaemon") {
                image.isTemplate = true
                button.image = image
            } else if let fallbackImage = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "GestureDaemon") {
                fallbackImage.isTemplate = true
                button.image = fallbackImage
            } else {
                button.title = "⌘G"
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
        Log.info("Menu bar status item initialized.")
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status Header
        let statusTitle = isPaused ? "GestureDaemon: Paused" : "GestureDaemon: Active"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // Pause / Resume Toggle
        let toggleTitle = isPaused ? "Resume Gestures" : "Pause Gestures"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(togglePause), keyEquivalent: "p")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemManager.shared.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        // Open Config
        let configItem = NSMenuItem(title: "Open Configuration File...", action: #selector(openConfigFile), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        // Check Permissions
        let permTitle = AccessibilityHelper.verifyAccessibility(prompt: false) ? "Accessibility: Granted" : "Accessibility: Not Granted..."
        let permItem = NSMenuItem(title: permTitle, action: #selector(checkPermissions), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit GestureDaemon", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func togglePause() {
        isPaused.toggle()
        EventTapManager.shared.isPaused = isPaused
        if let button = statusItem?.button {
            button.appearsDisabled = isPaused
        }
        Log.info(isPaused ? "Gestures paused from menu bar." : "Gestures resumed from menu bar.")
    }

    @objc private func toggleLaunchAtLogin() {
        let currentlyEnabled = LoginItemManager.shared.isLaunchAtLoginEnabled
        _ = LoginItemManager.shared.setLaunchAtLogin(enabled: !currentlyEnabled)
    }

    @objc private func openConfigFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let primaryPath = home.appendingPathComponent(".config/GestureDaemon/config.plist")
        if !FileManager.default.fileExists(atPath: primaryPath.path) {
            ConfigManager.shared.loadConfiguration()
        }
        NSWorkspace.shared.open(primaryPath)
    }

    @objc private func checkPermissions() {
        if !AccessibilityHelper.verifyAccessibility(prompt: true) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitApp() {
        EventTapManager.shared.stop()
        HIDPlusPlusManager.shared.stop()
        NSApplication.shared.terminate(nil)
    }
}

