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

        NotificationCenter.default.addObserver(
            forName: ConfigManager.configDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let show = ConfigManager.shared.activeConfig.showMenuBarIcon ?? true
            if show {
                self.isTemporarilyVisible = false
                self.createStatusItemIfNeeded()
                self.updateMenuBarIcon()
            } else if !self.isTemporarilyVisible {
                self.removeStatusItem()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .hidBatteryStatusDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateMenuBarIcon()
        }

        NotificationCenter.default.addObserver(
            forName: .hidHardwareCapabilitiesDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateMenuBarIcon()
        }
    }

    public func handleAppReopen() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Log.info("Application reopen triggered. Opening Preferences...")
            let wasHidden = (self.statusItem == nil)
            if wasHidden {
                self.isTemporarilyVisible = true
                self.createStatusItemIfNeeded()
            }
            PreferencesWindowController.shared.show()
        }
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
        updateMenuBarIcon()
        Log.info("Menu bar status item created.")
    }

    public func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let style = ConfigManager.shared.activeConfig.menuBarIconStyle ?? "standard"

        if style == "battery" || style == "batteryWithPercentage" {
            if let battery = HIDPlusPlusManager.shared.batteryInfo {
                button.image = makeMouseBatteryImage(battery: battery)
                if style == "batteryWithPercentage" {
                    button.title = " \(battery.percentage)%"
                } else {
                    button.title = ""
                }
            } else {
                if let image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Mouse") {
                    image.isTemplate = true
                    button.image = image
                }
                button.title = ""
            }
        } else {
            if let image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "GestureDaemon") {
                image.isTemplate = true
                button.image = image
            } else if let fallbackImage = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "GestureDaemon") {
                fallbackImage.isTemplate = true
                button.image = fallbackImage
            } else {
                button.title = "⌘G"
            }
            button.title = ""
        }

        button.appearsDisabled = isPaused
    }

    /// Renders a composite template icon combining a mouse silhouette and a battery level icon.
    /// This makes the menu bar item immediately distinguishable from the host Mac's own battery icon.
    private func makeMouseBatteryImage(battery: HIDPlusPlusManager.BatteryInfo) -> NSImage {
        let mouseSymbol = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)
        let batterySymbolName: String
        if battery.isCharging {
            batterySymbolName = "battery.100.bolt"
        } else {
            switch battery.percentage {
            case 85...100: batterySymbolName = "battery.100"
            case 60..<85:  batterySymbolName = "battery.75"
            case 35..<60:  batterySymbolName = "battery.50"
            case 15..<35:  batterySymbolName = "battery.25"
            default:       batterySymbolName = "battery.0"
            }
        }
        let batterySymbol = NSImage(systemSymbolName: batterySymbolName, accessibilityDescription: nil)

        let mouseW: CGFloat = 8
        let mouseH: CGFloat = 12
        let gap: CGFloat = 2.5
        let battW: CGFloat = 16
        let battH: CGFloat = 10
        let totalW = mouseW + gap + battW
        let totalH: CGFloat = 14

        let composite = NSImage(size: NSSize(width: totalW, height: totalH), flipped: false) { _ in
            let mouseRect = NSRect(x: 0, y: (totalH - mouseH) / 2, width: mouseW, height: mouseH)
            let battRect = NSRect(x: mouseW + gap, y: (totalH - battH) / 2, width: battW, height: battH)
            mouseSymbol?.draw(in: mouseRect)
            batterySymbol?.draw(in: battRect)
            return true
        }
        composite.isTemplate = true
        return composite
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

        // Zero-CPU Lazy Battery Refresh on user menu open
        HIDPlusPlusManager.shared.refreshBatteryStatus()

        // Status Header
        let statusTitle = isPaused ? "GestureDaemon (Paused)" : "GestureDaemon"
        let statusItemHeader = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItemHeader.image = NSImage(systemSymbolName: isPaused ? "pause.circle.fill" : "checkmark.circle.fill", accessibilityDescription: nil)
        statusItemHeader.isEnabled = false
        menu.addItem(statusItemHeader)

        // Connected Device Info with battery & icon
        if let devName = HIDPlusPlusManager.shared.connectedDeviceName {
            var devTitle = devName
            if let battery = HIDPlusPlusManager.shared.batteryInfo {
                let chargeStr = battery.isCharging ? " ⚡" : ""
                devTitle += "  ·  \(battery.percentage)%\(chargeStr)"
            }
            let devItem = NSMenuItem(title: devTitle, action: nil, keyEquivalent: "")

            let iconName: String
            if let battery = HIDPlusPlusManager.shared.batteryInfo {
                if battery.isCharging {
                    iconName = "battery.100.bolt"
                } else {
                    switch battery.percentage {
                    case 85...100: iconName = "battery.100"
                    case 60..<85:  iconName = "battery.75"
                    case 35..<60:  iconName = "battery.50"
                    case 15..<35:  iconName = "battery.25"
                    default:       iconName = "battery.0"
                    }
                }
            } else {
                iconName = "computermouse.fill"
            }
            devItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            devItem.isEnabled = false
            menu.addItem(devItem)
        } else {
            let devItem = NSMenuItem(title: "Searching...", action: nil, keyEquivalent: "")
            devItem.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)
            devItem.isEnabled = false
            menu.addItem(devItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Show/Hide Menu Bar Icon Options
        if isTemporarilyVisible {
            let keepItem = NSMenuItem(title: "Keep Menu Bar Icon Visible", action: #selector(keepMenuBarIconVisible), keyEquivalent: "")
            keepItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
            keepItem.target = self
            menu.addItem(keepItem)

            let rehideItem = NSMenuItem(title: "Hide Menu Bar Icon Again", action: #selector(rehideTemporarilyShownIcon), keyEquivalent: "")
            rehideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            rehideItem.target = self
            menu.addItem(rehideItem)
        } else {
            let hideItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
            hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            hideItem.target = self
            menu.addItem(hideItem)
        }

        // Icon Style Toggle (Static Gesture Icon vs Mouse Battery Icon)
        let currentStyle = ConfigManager.shared.activeConfig.menuBarIconStyle ?? "standard"
        let isBatterySelected = (currentStyle != "standard")
        let batteryToggleItem = NSMenuItem(
            title: isBatterySelected ? "Use Static Gesture Icon" : "Use Mouse Battery Icon",
            action: #selector(toggleBatteryMenuBarIcon),
            keyEquivalent: ""
        )
        batteryToggleItem.image = NSImage(
            systemSymbolName: isBatterySelected ? "cursorarrow.motionlines" : "battery.75",
            accessibilityDescription: nil
        )
        batteryToggleItem.target = self
        menu.addItem(batteryToggleItem)

        menu.addItem(NSMenuItem.separator())

        // Pause / Resume Toggle
        let toggleTitle = isPaused ? "Resume Gestures" : "Pause Gestures"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(togglePause), keyEquivalent: "p")
        toggleItem.image = NSImage(systemSymbolName: isPaused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        toggleItem.target = self
        menu.addItem(toggleItem)

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        loginItem.target = self
        loginItem.state = LoginItemManager.shared.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        // Preferences Window
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        prefsItem.target = self
        menu.addItem(prefsItem)

        // Permission Warnings (only displayed if action is required)
        let axGranted = PermissionHelper.isAccessibilityGranted
        let imGranted = PermissionHelper.isInputMonitoringGranted

        if !axGranted || !imGranted {
            menu.addItem(NSMenuItem.separator())
            if !axGranted {
                let axItem = NSMenuItem(title: "Accessibility: Missing (Authorize)", action: #selector(checkAccessibility), keyEquivalent: "")
                axItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                axItem.target = self
                menu.addItem(axItem)
            }
            if !imGranted {
                let imItem = NSMenuItem(title: "Input Monitoring: Missing (Authorize)", action: #selector(checkInputMonitoring), keyEquivalent: "")
                imItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                imItem.target = self
                menu.addItem(imItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit GestureDaemon", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
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

    @objc private func toggleBatteryMenuBarIcon() {
        let currentStyle = ConfigManager.shared.activeConfig.menuBarIconStyle ?? "standard"
        let nextStyle = (currentStyle == "standard") ? "battery" : "standard"
        ConfigManager.shared.updateMenuBarIconStyle(nextStyle)
        updateMenuBarIcon()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        EventTapManager.shared.isPaused = isPaused
        if let button = statusItem?.button {
            button.appearsDisabled = isPaused
        }
        if !isPaused {
            EventTapManager.shared.ensureTapActive()
            HIDPlusPlusManager.shared.handleWake()
        }
        Log.info(isPaused ? "Gestures paused from menu bar." : "Gestures resumed from menu bar.")
    }

    @objc private func toggleLaunchAtLogin() {
        let currentlyEnabled = LoginItemManager.shared.isLaunchAtLoginEnabled
        _ = LoginItemManager.shared.setLaunchAtLogin(enabled: !currentlyEnabled)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func checkAccessibility() {
        if !PermissionHelper.isAccessibilityGranted {
            _ = PermissionHelper.requestAccessibility()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func checkInputMonitoring() {
        if !PermissionHelper.isInputMonitoringGranted {
            _ = PermissionHelper.requestInputMonitoring()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
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
