import Cocoa

public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var isPaused = false
    public private(set) var isTemporarilyVisible = false

    public var hasVisibleStatusItem: Bool {
        return statusItem != nil
    }

    private override init() {
        super.init()
    }

    public func setup() {
        let shouldShow = ConfigManager.shared.activeConfig.showMenuBarIcon ?? true
        if shouldShow {
            createStatusItemIfNeeded()
        } else {
            Log.info("Menu bar icon hidden by user configuration.")
        }
    }

    public func handleAppReopen() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Log.info("Application reopen triggered. Making menu bar icon accessible...")
            let wasHidden = (self.statusItem == nil)
            if wasHidden {
                self.isTemporarilyVisible = true
            }
            self.createStatusItemIfNeeded()

            // Open the menu so the user immediately sees the controls
            if let button = self.statusItem?.button {
                button.performClick(nil)
            }
        }
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }

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
        Log.info("Menu bar status item created.")
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            Log.info("Menu bar status item removed.")
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status Header
        let statusTitle = isPaused ? "GestureDaemon: Paused" : "GestureDaemon: Active"
        let statusItemHeader = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItemHeader.isEnabled = false
        menu.addItem(statusItemHeader)

        menu.addItem(NSMenuItem.separator())

        // Show/Hide Menu Bar Icon Options
        if isTemporarilyVisible {
            let keepItem = NSMenuItem(title: "Keep Menu Bar Icon Visible", action: #selector(keepMenuBarIconVisible), keyEquivalent: "")
            keepItem.target = self
            menu.addItem(keepItem)

            let rehideItem = NSMenuItem(title: "Hide Menu Bar Icon Again", action: #selector(rehideTemporarilyShownIcon), keyEquivalent: "")
            rehideItem.target = self
            menu.addItem(rehideItem)
        } else {
            let hideItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
            hideItem.target = self
            menu.addItem(hideItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Pause / Resume Toggle
        let toggleTitle = isPaused ? "Resume Gestures" : "Pause Gestures"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(togglePause), keyEquivalent: "p")
        toggleItem.target = self
        menu.addItem(toggleItem)

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

    @objc private func hideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon?"
        alert.informativeText = "GestureDaemon will continue running smoothly in the background.\n\nTo bring the menu bar icon back or access settings anytime, simply re-launch GestureDaemon from Applications or Spotlight."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            ConfigManager.shared.updateShowMenuBarIcon(false)
            isTemporarilyVisible = false
            removeStatusItem()
        }
    }

    @objc private func keepMenuBarIconVisible() {
        ConfigManager.shared.updateShowMenuBarIcon(true)
        isTemporarilyVisible = false
    }

    @objc private func rehideTemporarilyShownIcon() {
        isTemporarilyVisible = false
        removeStatusItem()
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
