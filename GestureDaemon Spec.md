# ENGINEERING SPECIFICATION & AGENT PROMPT: NATIVE MACOS GESTURE ENGINE (GestureDaemon)

Revision 2 — fixes applied to a prior draft. Changes from the original are called out inline as `[FIX]` so you can see what was wrong and why.

## 1. Executive Summary & Objective

Zero-dependency, ultra-lightweight background daemon for macOS (`GestureDaemon`) replacing Logitech Options+ for multi-button mice (e.g. Logitech M720 Triathlon). Intercepts hardware mouse events globally via a Quartz event tap, evaluates spatial drag thresholds against a user-editable `config.plist`, and dispatches native macOS shortcuts, app launches, or shell commands.

### Key Architectural Tenets
- **Zero external dependencies** — CoreGraphics, IOKit, AppKit, Foundation, os.log only.
- **Deterministic state machine** — clean separation of clicks vs. directional swipes, no cursor stutter.
- **Configuration driven** — button IDs, thresholds, deadzones, and actions parsed at launch and hot-reloaded from `config.plist`.
- **Resilient event tap** — self-heals on `kCGEventTapDisabledByTimeout` / `ByUserInput`.
- **Low footprint** — no UI process, no persistent windows. Target < 15 MB RAM, ~0% idle CPU.

`[FIX]` Dropped the "Headless / Agent Mode via `LSUIElement`" framing. `LSUIElement` only affects `.app` bundles that Launch Services registers (Dock/menu bar visibility). This build produces a bare Mach-O executable launched by `launchd` — it has no windows, no `NSApplication` run loop, and therefore no Dock presence *regardless* of `Info.plist`. The plist is kept below for documentation/future GUI-bundling only; it is not embedded or read by the OS in this build path.

## 2. Technical Stack & Target Specification

| Parameter | Value |
|---|---|
| Language | Swift 5.9+ |
| Toolchain | Xcode 15+ Command Line Tools (`swiftc`) |
| Target OS | macOS 13.0+ (Ventura, Sonoma, Sequoia+) |
| Architecture | Universal binary (arm64 + x86_64), built via `lipo` |
| Sandboxing | Disabled (`com.apple.security.app-sandbox = false`) |
| Required privileges | Accessibility (`AXIsProcessTrusted`) — **not** Input Monitoring, since this only taps mouse events and posts synthetic keyboard output; Input Monitoring is only required to *listen* to hardware keyboard events |
| Config location | `~/.config/GestureDaemon/config.plist` (fallback `~/Library/Application Support/GestureDaemon/config.plist`) |

## 3. Architecture & System Flow

```
                                 [ Hardware Input: Logitech M720 ]
                                                 │
                                                 ▼
                                     [ Quartz Event Tap ]
                          (CGEventMask: otherMouseDown/Up/Dragged only)
                                                 │
                     ┌───────────────────────────┴───────────────────────────┐
                     ▼                                                       ▼
            [ Other Mouse Event ]                                   [ Drag Event ]
          (Buttons 2, 3, 4, 5, ...)                          (otherMouseDragged delta)
                     │                                                       │
                     └───────────────────────────┬───────────────────────────┘
                                                 ▼
                                     [ GestureStateMachine ]
                                                 │
                 ┌───────────────────────────────┴───────────────────────────────┐
                 ▼                                                               ▼
        [ Stationary Click ]                                            [ Directional Drag ]
     - Within deadzone radius                                        - Exceeds threshold (e.g. 35pt)
     - Released before threshold                                     - Direction: Left / Right / Up / Down
                 │                                                               │
                 └───────────────────────────────┬───────────────────────────────┘
                                                 ▼
                                     [ Config Action Router ]
                     ┌───────────────────────────┼───────────────────────────┐
                     ▼                           ▼                           ▼
            [ Synthetic Keypress ]      [ Launch System App ]        [ Shell Command ]
```

`[FIX]` Removed `.mouseMoved` from the tapped event mask. `.mouseMoved` fires continuously whenever *no* mouse button is held, system-wide — capturing it defeats the "~0% idle CPU" goal for no functional gain, since drag detection while the trigger button is held is delivered as `.otherMouseDragged`, not `.mouseMoved`.

## 4. Hardware Button Mapping Matrix (Logitech M720)

| Physical Control | Quartz Button Number | Event Type | Default Purpose |
|---|---|---|---|
| Left Primary Click | 0 | `.leftMouseDown/Up` | Bypassed (not tapped) |
| Right Secondary Click | 1 | `.rightMouseDown/Up` | Bypassed (not tapped) |
| Middle Wheel Click | 2 | `.otherMouseDown` | Pass-through |
| Thumb Back | 3 | `.otherMouseDown` | Pass-through / custom |
| Thumb Forward | 4 | `.otherMouseDown` | Pass-through / custom |
| Hidden Thumb Pad | 5 (or 6 on some FW) | `.otherMouseDown` | Primary gesture trigger |

Run `./build/GestureDaemon --diagnostics` and click the thumb pad to confirm the actual index on your unit/firmware before relying on the default (5).

## 5. Complete File Layout

```
GestureDaemon/
├── Makefile
├── GestureDaemon.entitlements
├── GestureDaemon/
│   ├── Info.plist
│   ├── main.swift
│   ├── Configuration/
│   │   ├── ConfigManager.swift
│   │   └── config.plist
│   ├── Core/
│   │   ├── EventTapManager.swift
│   │   ├── GestureStateMachine.swift
│   │   └── ActionDispatcher.swift
│   └── Utilities/
│       ├── AccessibilityHelper.swift
│       └── Logger.swift
└── scripts/
    ├── install.sh
    ├── uninstall.sh
    └── com.user.gesturedaemon.plist
```

`[FIX]` The LaunchAgent filename in the original doc contained corrupted/garbled characters (`com.user.gestu[garbled]daem[garbled].plist`) that didn't match what the Makefile referenced. Standardized to `com.user.gesturedaemon.plist` everywhere.

## 6. Source

### 6.1 Entitlements & Info.plist

`GestureDaemon.entitlements`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

`GestureDaemon/Info.plist` (documentation only — not embedded in this build; see note in §1)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.user.GestureDaemon</string>
    <key>CFBundleName</key>
    <string>GestureDaemon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

### 6.2 Configuration Template (`config.plist`)

Unchanged from the original draft — mapping is sound. One addition:

`[FIX]` `ActionDefinition.command` shells out via `/bin/zsh -c <string from plist>`. Since anything with write access to `~/.config/GestureDaemon/config.plist` can execute arbitrary shell commands as you, lock the file down after install:
```bash
chmod 600 ~/.config/GestureDaemon/config.plist
```
This is noted in `install.sh` below.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>TriggerButtonIndex</key>
    <integer>5</integer>
    <key>ThresholdDistance</key>
    <real>35.0</real>
    <key>DeadzoneRadius</key>
    <real>8.0</real>
    <key>SwallowTriggerEvents</key>
    <true/>
    <key>ClickAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>126</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Mission Control (Ctrl+Up)</string>
    </dict>
    <key>DragLeftAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>123</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Space Left (Ctrl+Left)</string>
    </dict>
    <key>DragRightAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>124</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Space Right (Ctrl+Right)</string>
    </dict>
    <key>DragUpAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>126</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Mission Control</string>
    </dict>
    <key>DragDownAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>125</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>App Expose (Ctrl+Down)</string>
    </dict>
</dict>
</plist>
```

### 6.3 Logger & Accessibility Helper

`GestureDaemon/Utilities/Logger.swift`
```swift
import Foundation
import os.log

public enum Log {
    private static let logger = Logger(subsystem: "com.user.GestureDaemon", category: "Core")

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        print("[INFO] \(message)")
    }
    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        print("[ERROR] \(message)")
    }
    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
        print("[DEBUG] \(message)")
        #endif
    }
}
```

`GestureDaemon/Utilities/AccessibilityHelper.swift`
```swift
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
```

### 6.4 Configuration Engine

`GestureDaemon/Configuration/ConfigManager.swift`
```swift
import Foundation

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

public struct AppConfig: Codable {
    public let triggerButtonIndex: Int64
    public let thresholdDistance: Double
    public let deadzoneRadius: Double
    public let swallowTriggerEvents: Bool
    public let clickAction: ActionDefinition?
    public let dragLeftAction: ActionDefinition?
    public let dragRightAction: ActionDefinition?
    public let dragUpAction: ActionDefinition?
    public let dragDownAction: ActionDefinition?

    enum CodingKeys: String, CodingKey {
        case triggerButtonIndex = "TriggerButtonIndex"
        case thresholdDistance = "ThresholdDistance"
        case deadzoneRadius = "DeadzoneRadius"
        case swallowTriggerEvents = "SwallowTriggerEvents"
        case clickAction = "ClickAction"
        case dragLeftAction = "DragLeftAction"
        case dragRightAction = "DragRightAction"
        case dragUpAction = "DragUpAction"
        case dragDownAction = "DragDownAction"
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
        if fileManager.fileExists(atPath: primaryPath.path) { return primaryPath }
        return home.appendingPathComponent("Library/Application Support/GestureDaemon/config.plist")
    }

    private init() {
        self.activeConfig = ConfigManager.fallbackDefaultConfig()
        loadConfiguration()
        startMonitoringConfigFile()
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
            triggerButtonIndex: 5, thresholdDistance: 35.0, deadzoneRadius: 8.0, swallowTriggerEvents: true,
            clickAction: ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragLeftAction: ActionDefinition(type: .shortcut, keyCode: 123, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragRightAction: ActionDefinition(type: .shortcut, keyCode: 124, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragUpAction: ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil),
            dragDownAction: ActionDefinition(type: .shortcut, keyCode: 125, modifiers: ["Control"], bundleIdentifier: nil, commandPath: nil)
        )
    }
}
```
`[FIX]` Added `setAttributes(.posixPermissions: 0o600)` when writing the default config, matching the §6.2 security note.

### 6.5 Action Dispatcher

`GestureDaemon/Core/ActionDispatcher.swift`
```swift
import Cocoa

public final class ActionDispatcher {
    public static let shared = ActionDispatcher()
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    public func dispatch(action: ActionDefinition?) {
        guard let action = action else { return }
        switch action.type {
        case .shortcut:
            guard let keyCode = action.keyCode else { return }
            sendSyntheticShortcut(keyCode: CGKeyCode(keyCode), flags: parseModifierFlags(action.modifiers ?? []))
        case .application:
            guard let bundleId = action.bundleIdentifier,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        case .command:
            guard let command = action.commandPath else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            try? process.run()
        }
    }

    private func sendSyntheticShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            Log.error("Failed to construct CGEvents for keycode \(keyCode)")
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000)
        keyUp.post(tap: .cghidEventTap)
    }

    private func parseModifierFlags(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "control", "ctrl": flags.insert(.maskControl)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "command", "cmd": flags.insert(.maskCommand)
            default: break
            }
        }
        return flags
    }
}
```

### 6.6 Gesture State Machine

`GestureDaemon/Core/GestureStateMachine.swift`
```swift
import Foundation
import CoreGraphics

public enum GestureDirection { case left, right, up, down }

public final class GestureStateMachine {
    private var isTriggerEngaged = false
    private var accumulatedDeltaX: Double = 0.0
    private var accumulatedDeltaY: Double = 0.0
    private var gestureConsumed = false

    public init() {}

    public func handleButtonDown(buttonNumber: Int64) -> Bool {
        let config = ConfigManager.shared.activeConfig
        guard buttonNumber == config.triggerButtonIndex else { return false }
        isTriggerEngaged = true
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        return config.swallowTriggerEvents
    }

    public func handleMouseDragged(deltaX: Double, deltaY: Double) -> Bool {
        guard isTriggerEngaged else { return false }
        let config = ConfigManager.shared.activeConfig
        accumulatedDeltaX += deltaX
        accumulatedDeltaY += deltaY
        let distance = hypot(accumulatedDeltaX, accumulatedDeltaY)
        if distance < config.deadzoneRadius { return config.swallowTriggerEvents }
        if distance >= config.thresholdDistance && !gestureConsumed {
            gestureConsumed = true
            executeDirectionalAction(resolveDirection(dx: accumulatedDeltaX, dy: accumulatedDeltaY))
        }
        return config.swallowTriggerEvents
    }

    public func handleButtonUp(buttonNumber: Int64) -> Bool {
        let config = ConfigManager.shared.activeConfig
        guard buttonNumber == config.triggerButtonIndex else { return false }
        if isTriggerEngaged && !gestureConsumed {
            Log.info("Click detected on trigger button (\(buttonNumber))")
            ActionDispatcher.shared.dispatch(action: config.clickAction)
        }
        isTriggerEngaged = false
        accumulatedDeltaX = 0.0
        accumulatedDeltaY = 0.0
        gestureConsumed = false
        return config.swallowTriggerEvents
    }

    private func resolveDirection(dx: Double, dy: Double) -> GestureDirection {
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func executeDirectionalAction(_ direction: GestureDirection) {
        let config = ConfigManager.shared.activeConfig
        switch direction {
        case .left:  Log.info("Gesture: Drag Left");  ActionDispatcher.shared.dispatch(action: config.dragLeftAction)
        case .right: Log.info("Gesture: Drag Right"); ActionDispatcher.shared.dispatch(action: config.dragRightAction)
        case .up:    Log.info("Gesture: Drag Up");    ActionDispatcher.shared.dispatch(action: config.dragUpAction)
        case .down:  Log.info("Gesture: Drag Down");  ActionDispatcher.shared.dispatch(action: config.dragDownAction)
        }
    }
}
```
Note: gestures fire once per button-hold (no re-fire on continued movement past threshold, no re-fire on direction reversal mid-drag). This is intentional — release and re-press to fire again.

### 6.7 Event Tap Manager & Watchdog

`GestureDaemon/Core/EventTapManager.swift`
```swift
import Cocoa
import CoreGraphics

public final class EventTapManager {
    public static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let stateMachine = GestureStateMachine()
    private var diagnosticMode = false

    private init() {}

    public func enableDiagnostics(_ enabled: Bool) { self.diagnosticMode = enabled }

    public func start() {
        // [FIX] Removed .mouseMoved — it fires on every cursor move with no button
        // held, system-wide, defeating the idle-CPU goal. Drag detection while the
        // trigger button is held arrives as .otherMouseDragged.
        let eventMask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
                                  | (1 << CGEventType.otherMouseUp.rawValue)
                                  | (1 << CGEventType.otherMouseDragged.rawValue)

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            Log.error("Failed to create CGEventTap. Check Accessibility permission.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEventTapEnable(tap, true) // [FIX] positional args, not keyword labels
        Log.info("CGEventTap engaged.")
    }

    public func stop() {
        guard let tap = eventTap else { return }
        CGEventTapEnable(tap, false) // [FIX] positional args
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        self.eventTap = nil
        self.runLoopSource = nil
        Log.info("CGEventTap disconnected.")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.error("EventTap disabled by macOS. Re-enabling...")
            if let tap = eventTap { CGEventTapEnable(tap, true) } // [FIX]
            return Unmanaged.passRetained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        if diagnosticMode && (type == .otherMouseDown || type == .otherMouseUp) {
            print("[DIAGNOSTIC] Event Type: \(type.rawValue), ButtonNumber: \(buttonNumber)")
        }

        var shouldSuppress = false
        switch type {
        case .otherMouseDown:
            shouldSuppress = stateMachine.handleButtonDown(buttonNumber: buttonNumber)
        case .otherMouseDragged:
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            shouldSuppress = stateMachine.handleMouseDragged(deltaX: dx, deltaY: dy)
        case .otherMouseUp:
            shouldSuppress = stateMachine.handleButtonUp(buttonNumber: buttonNumber)
        default:
            break
        }

        return shouldSuppress ? nil : Unmanaged.passRetained(event)
    }
}
```

### 6.8 Main Entrypoint

`GestureDaemon/main.swift`
```swift
import Cocoa

let args = CommandLine.arguments
let isDiagnostics = args.contains("--diagnostics")

Log.info("Launching GestureDaemon...")

if isDiagnostics {
    Log.info("DIAGNOSTIC mode: button indices will print to stdout.")
    EventTapManager.shared.enableDiagnostics(true)
}

_ = ConfigManager.shared

if !AccessibilityHelper.verifyAccessibility(prompt: true) {
    Log.error("Accessibility permission missing. System prompt shown.")
}

AccessibilityHelper.pollForAccess {
    Log.info("Starting EventTap...")
    EventTapManager.shared.start()
}

// [FIX] Graceful shutdown so `stop()` actually runs instead of the process
// being killed mid-tap by launchd/SIGTERM.
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
sigtermSource.setEventHandler {
    Log.info("SIGTERM received. Shutting down.")
    EventTapManager.shared.stop()
    exit(0)
}
sigtermSource.resume()

RunLoop.current.run(mode: .default, before: .distantFuture)
```

## 7. Build Automation: Makefile

`[FIX]` Three changes from the original:
1. Universal binary via two `swiftc` invocations + `lipo -create`.
2. Stable code-sign identifier (`--identifier`) so Accessibility permission survives rebuilds.
3. `sudo` scoped to only the binary-copy line, not the whole `make install` invocation — `launchctl load` must run as your user, not root, or the LaunchAgent registers in the wrong session and silently never starts at login.

```makefile
SWIFTC=swiftc
TARGET=GestureDaemon
BUNDLE_ID=com.user.GestureDaemon
BUILD_DIR=./build
SRC=$(shell find GestureDaemon -name "*.swift")
ENTITLEMENTS=GestureDaemon.entitlements
INSTALL_BIN=/usr/local/bin/$(TARGET)
LAUNCH_AGENT_DIR=$(HOME)/Library/LaunchAgents
AGENT_PLIST=scripts/com.user.gesturedaemon.plist
SDK=$(shell xcrun --show-sdk-path)

all: clean build

build:
	@echo "==> Compiling GestureDaemon (arm64 + x86_64)..."
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) -O -target arm64-apple-macos13.0 -sdk $(SDK) $(SRC) -o $(BUILD_DIR)/$(TARGET)-arm64
	$(SWIFTC) -O -target x86_64-apple-macos13.0 -sdk $(SDK) $(SRC) -o $(BUILD_DIR)/$(TARGET)-x86_64
	@echo "==> Fusing universal binary..."
	lipo -create -output $(BUILD_DIR)/$(TARGET) $(BUILD_DIR)/$(TARGET)-arm64 $(BUILD_DIR)/$(TARGET)-x86_64
	@echo "==> Code signing (stable identifier: $(BUNDLE_ID))..."
	codesign --force --sign - --identifier "$(BUNDLE_ID)" --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(TARGET)
	@echo "==> Build complete: $(BUILD_DIR)/$(TARGET)"

diagnose: build
	@echo "==> Diagnostic mode. Ctrl+C to exit."
	$(BUILD_DIR)/$(TARGET) --diagnostics

# NOTE: run as `make install`, NOT `sudo make install`. sudo is scoped to the
# one line that needs root; everything else (config dir, LaunchAgent) must be
# written and loaded as your own user, not root, or launchctl load registers
# in the wrong session.
install: build
	@echo "==> Installing binary (will prompt for sudo password)..."
	sudo install -m 755 $(BUILD_DIR)/$(TARGET) $(INSTALL_BIN)
	@mkdir -p $(HOME)/.config/GestureDaemon
	@if [ ! -f $(HOME)/.config/GestureDaemon/config.plist ]; then \
		cp GestureDaemon/Configuration/config.plist $(HOME)/.config/GestureDaemon/config.plist; \
		chmod 600 $(HOME)/.config/GestureDaemon/config.plist; \
		echo "==> Default config written to $(HOME)/.config/GestureDaemon/config.plist"; \
	fi
	@mkdir -p $(LAUNCH_AGENT_DIR)
	@cp $(AGENT_PLIST) $(LAUNCH_AGENT_DIR)/
	@launchctl unload $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist 2>/dev/null || true
	launchctl load $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist
	@echo "==> Installed and loaded."

uninstall:
	@launchctl unload $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist 2>/dev/null || true
	@rm -f $(LAUNCH_AGENT_DIR)/com.user.gesturedaemon.plist
	sudo rm -f $(INSTALL_BIN)
	@echo "==> Binary removed. Config preserved at ~/.config/GestureDaemon"

clean:
	@rm -rf $(BUILD_DIR)
```

## 8. Persistence: LaunchAgent Plist

`scripts/com.user.gesturedaemon.plist`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.gesturedaemon</string>
    <key>ProgramArguments</key>
    <array><string>/usr/local/bin/GestureDaemon</string></array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
        <key>Crashed</key><true/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/tmp/GestureDaemon.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/GestureDaemon.stderr.log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```
`[FIX]` Added `ThrottleInterval` (5s) so a crash-on-launch bug doesn't spin `launchd` into a rapid respawn loop.

## 9. Verification, Diagnostics & Calibration

**Step 1 — Pre-flight cleanup**
```bash
killall "Logi Options+" "LogiMgrDaemon" "logioptionsplus_agent" 2>/dev/null || true
sudo rm -rf "/Library/Application Support/Logitech.localized/LogiOptionsPlus" 2>/dev/null || true
```

**Step 2 — Confirm thumb button index**
```bash
make diagnose
```
Click the thumb pad; expect `[DIAGNOSTIC] Event Type: 25, ButtonNumber: 5`. If it prints a different number, update `TriggerButtonIndex` in `~/.config/GestureDaemon/config.plist`.

**Step 3 — Grant Accessibility**
On first run, System Settings → Privacy & Security → Accessibility will prompt. Approve for the built binary (or your terminal app if running via `make diagnose`). Because the binary is now signed with a stable `--identifier`, this grant survives future `make build` runs.

**Step 4 — Install**
```bash
make install     # NOT sudo make install — see §7 note
```

**Step 5 — Verification matrix**

| Action | Gesture | Expected Behavior |
|---|---|---|
| Click | Tap thumb button | Mission Control opens |
| Swipe Left | Hold + push left ~35pt | Switch to left Space |
| Swipe Right | Hold + push right ~35pt | Switch to right Space |
| Standard click | Left/right click normally | Unaffected, no dropped events |

## 10. Agent Execution Instructions

```
You are an autonomous macOS systems engineer. Execute step-by-step:

1. Scaffold the directory tree in §5.
2. Write each file exactly as declared in §6, §7, §8. No placeholders.
3. Run `make build`. Confirm it produces a universal binary (`lipo -info build/GestureDaemon` should list both arm64 and x86_64) and that codesign succeeds with the stable identifier.
4. Run `./build/GestureDaemon --diagnostics` and confirm the M720 thumb button maps to button index 5 (adjust config if not).
5. Run `make install` — NOT `sudo make install`. Confirm via `launchctl list | grep gesturedaemon` that the agent is loaded in the user session, not root's.
6. Confirm `~/.config/GestureDaemon/config.plist` exists with mode 600.
7. Check `/tmp/GestureDaemon.stdout.log` and `/tmp/GestureDaemon.stderr.log` for zero startup crashes and successful EventTap initialization.
8. Manually verify all four rows of the §9 verification matrix.
```
