# GestureDaemon: Architecture, Configuration Guide & Roadmap

**GestureDaemon** is a lightweight, zero-telemetry, zero-external-dependency native macOS background daemon and menu bar application designed to replace heavy proprietary software like Logitech Options+ for multi-button mice (including the Logitech M720 Triathlon and MX Master series).

Written in pure Swift using low-level Apple frameworks (`CoreGraphics`, `IOKit`, `AppKit`, `ServiceManagement`), it provides sub-millisecond gesture response times, fluid macOS Spaces and Mission Control switching, and maintains a strict **0.0% idle CPU** footprint.

---

## Table of Contents

1. [Project Overview & Key Milestones (What Has Been Done)](#1-project-overview--key-milestones-what-has-been-done)
   - [Native macOS Agent Bundle & Application Lifecycle](#a-native-macos-agent-bundle--application-lifecycle)
   - [Modern Background Services (SMAppService)](#b-modern-background-services-smappservice)
   - [Menu Bar Controller & Headless Reopen Recovery](#c-menu-bar-controller--headless-reopen-recovery)
   - [Dual-Engine Input Capture & Modifier Sanitization](#d-dual-engine-input-capture--modifier-sanitization)
   - [WindowServer Spaces & Mission Control Integration](#e-windowserver-spaces--mission-control-integration)
   - [Zero-Overhead Ephemeral Dynamic Motion Tap (0.0% CPU)](#f-zero-overhead-ephemeral-dynamic-motion-tap-00-cpu)
   - [Standard macOS DMG Packaging](#g-standard-macos-dmg-packaging)
   - [Universal Side Navigation Buttons & Low-Level HID Injection](#h-universal-side-navigation-buttons--low-level-hid-injection)
   - [Per-Application Contextual Profiles](#i-per-application-contextual-profiles)
   - [Real-Time File Logging (daemon.log)](#j-real-time-file-logging-daemonlog)
   - [Direct Bluetooth LE HID++ Hardware Engine](#k-direct-bluetooth-le-hid-hardware-engine)
   - [Sleep / Wake & Power Resilience Engine](#l-sleep--wake--power-resilience-engine)
   - [SwiftUI Native Preferences Window & Keycode Resolver](#m-swiftui-native-preferences-window--keycode-resolver)
2. [Complete Configuration Guide (config.plist)](#2-complete-configuration-guide-configplist)
   - [Configuration Locations & Priority](#configuration-locations--priority)
   - [Live Hot-Reloading](#live-hot-reloading)
   - [Configuration Schema & Parameter Reference](#configuration-schema--parameter-reference)
   - [Action Types & Syntax](#action-types--syntax)
   - [Virtual KeyCode Reference Table & Layout Mapping](#virtual-keycode-reference-table)
   - [Per-Application Contextual Profiles (Applications)](#per-application-contextual-profiles-applications)
   - [Real-World Configuration Recipes](#real-world-configuration-recipes)
3. [Future Roadmap (What We Can Do Next)](#3-future-roadmap-what-we-can-do-next)
   - [Diagonal & 8-Way Gesture Recognition](#1-diagonal--8-way-gesture-recognition)
   - [Haptic Feedback Integration](#2-haptic-feedback-integration)
   - [Developer ID Signing & Notarization Pipeline](#3-developer-id-signing--notarization-pipeline)

---

## 1. Project Overview & Key Milestones (What Has Been Done)

### A. Native macOS Agent Bundle & Application Lifecycle
- **Agent Mode (`LSUIElement = true`)**: The application runs as an unobtrusive background agent without cluttering the macOS Dock or creating unnecessary empty windows.
- **Persistent Accessibility Authorizations**: Packaged as `GestureDaemon.app` with bundle identifier `com.guru.GestureDaemon`, ensuring macOS Accessibility permissions persist across system reboots and updates without dropping out of `TCC.db`.
- **Universal Mach-O Architecture**: Compiled for both Apple Silicon (`arm64`) and Intel (`x86_64`) via `lipo`, ensuring native performance on all modern Macs.

### B. Modern Background Services (`SMAppService`)
- Replaced legacy, deprecated raw `launchctl` shell scripts with Apple's modern **`ServiceManagement.SMAppService.mainApp`** API.
- Fully integrated with macOS **System Settings → General → Login Items & Extensions**, allowing users to manage launch privileges natively or toggle them directly from the menu bar.

### C. Menu Bar Controller & Headless Reopen Recovery
- Implemented `MenuBarController` (`NSStatusItem`) providing quick visibility into daemon status, live pause/resume toggling, single-click access to config files, and permission validation.
- **Hide Menu Bar Icon Support**: Users can choose to hide the status item from the menu bar (`ShowMenuBarIcon = false`).
- **Single-Instance Reopen Recovery**: If the menu bar icon is hidden and the daemon is running, attempting to re-open `GestureDaemon.app` (from Spotlight, Finder, `/Applications`, or CLI) triggers `applicationShouldHandleReopen` and broadcasts a message across `DistributedNotificationCenter`. The running daemon temporarily restores the menu bar item and displays the menu, giving the user instant access to quit, change settings, or restore the icon.

### D. Dual-Engine Input Capture & Modifier Sanitization
- **IOKit HID++ Hardware Engine (`HIDPlusPlusManager`)**: Directly interfaces with Logitech Unifying and Bolt USB receivers via `IOHIDManager` on vendor usage page `0xFF00`, bypassing standard OS mouse restrictions.
- **Quartz EventTap Engine (`EventTapManager`)**: Intercepts physical mouse buttons (Button 3, 4, 5) and Logitech's hardware fallback thumb button macro (`Cmd + Option + Tab`, Virtual KeyCode `48`).
- **Modifier Sanitization & VS Code Focus Fix**:
  - The thumb button hardware macro produces a `Tab` keystroke surrounded by Command and Option modifiers.
  - `EventTapManager` unconditionally catches and swallows the `Tab` event and flushes system modifier flags using a synthetic empty `flagsChanged` event posted to `.cghidEventTap`.
  - This ensures applications like VS Code or browser tab bars never steal focus or activate app switchers when the gesture button is clicked.

### E. WindowServer Spaces & Mission Control Integration
- **OpenLogi CGS Architecture**: Ported reverse-engineered CoreGraphics Services (CGS) private SPI from the open-source `OpenLogi` project.
- **Spaces Switching**: Uses `CGSGetSymbolicHotKeyValue` to query macOS Symbolic HotKeys `79` (Move left a space) and `81` (Move right a space). Synthesizes key events with the required `NX_SECONDARYFNMASK` (`0x800000`) and `Control` (`0x40000`) flags (`0x840000`), dispatching directly to `CGEventTapLocation.cgSessionEventTap`.
- **Mission Control & App Exposé**: Dispatches instant Exposé transitions using `CoreDockSendNotification("com.apple.expose.awake")` and `"com.apple.expose.front.awake"`.
- **Natural Swipe Physics**: Configured natural swipe directions matching macOS trackpad gestures:
  - **Drag Left** $\rightarrow$ Switch to Right Space (`KeyCode: 124` / HotKey `81`)
  - **Drag Right** $\rightarrow$ Switch to Left Space (`KeyCode: 123` / HotKey `79`)
  - **Stationary Click / Tap** $\rightarrow$ Mission Control (`com.apple.expose.awake`)
  - **Drag Down** $\rightarrow$ App Exposé (`com.apple.expose.front.awake`)
- **Latency Optimization**: Reduced the gesture evaluation window to **`75ms`**, making single clicks feel snappy and instantaneous while preserving reliable flick detection.

### F. Zero-Overhead Ephemeral Dynamic Motion Tap (0.0% CPU)
- **Root Cause of Previous CPU Spikes**:
  - In CoreGraphics, calling `CGEvent.tapEnable(tap, false)` notifies the tap callback with `kCGEventTapDisabledByUserInput`. The original code treated this as an unexpected error and automatically re-enabled the tap.
  - This caused a persistent `mouseMoved` tap to run constantly. Touchpads emit 120–240 sub-pixel events per second on ProMotion displays, forcing `WindowServer` to perform hundreds of synchronous Mach IPC context switches into `GestureDaemon` every second.
- **The Ephemeral Lifecycle Solution**:
  - At daemon startup, **no motion tap exists** (`motionEventTap = nil`). `primaryEventTap` strictly listens to button clicks, keys, and modifier changes.
  - When the user presses the gesture trigger, `startMotionTap()` creates the `mouseMoved` tap dynamically for the duration of the 75ms window.
  - As soon as the swipe threshold is crossed or the stationary click timer expires, `stopMotionTap()` calls `CFMachPortInvalidate(tap)` and removes the run loop source, unregistering the tap from `WindowServer`.
  - **Result**: Moving the trackpad or mouse during normal operation produces **zero Mach messages, zero context switches, and steady 0.0% CPU**.

### G. Standard macOS DMG Packaging
- Created `scripts/create_dmg.sh` and `make dmg` targets to generate `build/GestureDaemon.dmg` with an embedded `/Applications` drag-and-drop symlink and custom multi-resolution icon (`AppIcon.icns`).

### H. Universal Side Navigation Buttons & Low-Level HID Injection
- **Problem**: Standard mouse thumb buttons (Button 3 & Button 4) are typically ignored by macOS Safari, Chrome, and Finder unless remapped.
- **Solution**:
  - `EventTapManager` captures Button 3 (Back) and Button 4 (Forward), swallows raw mouse down/up/drag events, and executes context-aware navigation.
  - In standard macOS applications (Safari, Chrome, Finder, System Settings), dispatches `Cmd + [` and `Cmd + ]`.
  - In code editors (Visual Studio Code, VSCodium), dispatches editor history navigation (`Ctrl + -` and `Ctrl + Shift + -`).
  - **Low-Level HID Injection (`.cghidEventTap`)**: While system apps intercept shortcuts at the menu level (`.cgSessionEventTap`), Electron and Chromium applications (like VS Code) process keyboard input through the low-level HID subsystem. Keystrokes are injected directly into `.cghidEventTap` with hardware device modifier flags (`NX_DEVICELCTLKEYMASK`), ensuring seamless delivery to all GUI frameworks.

### I. Per-Application Contextual Profiles
- Dynamic gesture and button remapping based on the frontmost application.
- `ConfigManager` synchronously evaluates `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` and matches defined profiles under `<key>Applications</key>` in `config.plist`.
- Any gesture or button omitted in an app profile gracefully falls back to your global configuration, offering complete flexibility with zero configuration boilerplate.

### J. Configurable Logging & Level Selection (`daemon.log`)
- Logging is **disabled by default** (`EnableLogging = false`) to guarantee absolute zero disk I/O and 0.0% idle CPU consumption.
- Can be activated dynamically via `config.plist` with live hot-reloading (no restart required).
- Supports granular log levels: `"Debug"`, `"Info"`, `"Error"`, and `"None"`.
- When enabled, logs button presses, frontmost application detections, resolved actions, and gesture states to `~/.config/GestureDaemon/daemon.log` (`tail -f ~/.config/GestureDaemon/daemon.log`).
- Running interactive hardware diagnostics (`make diagnose` or `--diagnostics`) automatically forces active debug logging regardless of config settings.

### K. Direct Bluetooth LE HID++ Hardware Engine
- **Dual-Transport Auto-Detection**: `HIDPlusPlusManager` seamlessly interfaces with both USB Unifying/Bolt receivers (`VendorID: 0x046d`, `UsagePage: 0xff00`) and direct **Bluetooth Low Energy** connections (`UsagePage: 0xff43`, `Usage: 0x0202`).
- **HID++ 2.0 Long-Report Framing (`0x11`)**: Direct BLE links require 20-byte Long Reports addressed to device index `0xFF`. The engine formats, pads, and dispatches HID++ 2.0 commands accordingly.
- **Dynamic Feature Discovery (IRoot `0x0000`)**: Queries the device at connection time to resolve the runtime feature index for `0x1B04` (`REPROG_CONTROLS_V4`).
- **Hardware Button Diversion**: Automatically issues `setCidReporting` for Logitech gesture controls (CID `0x00C3` Gesture Button, `0x00D0`, and `0x01A0`), instructing the firmware to divert clicks directly into `GestureDaemon` instead of emitting OS fallback macros.
- **Permission Management**: Direct Bluetooth composite HID access requires macOS **Input Monitoring** permissions (`IOHIDCheckAccess`). `PermissionHelper` checks and prompts for Input Monitoring alongside Accessibility, displaying real-time status and single-click recovery directly in the menu bar.

### L. Sleep / Wake & Power Resilience Engine
- **The Challenge**: When macOS enters display sleep, system sleep, or screen lock, CoreGraphics automatically disables user-space event taps (`kCGEventTapDisabledByUserInput`). Simultaneously, Bluetooth Low Energy peripherals power-cycle their microcontrollers, resetting internal firmware memory (Feature `0x1B04` `REPROG_CONTROLS_V4`) back to un-diverted factory defaults.
- **Dedicated Power Manager (`SleepWakeManager`)**:
  - Implements closure block observers on `NSWorkspace.shared.notificationCenter` for `willSleepNotification`, `didWakeNotification`, `screensDidSleepNotification`, `screensDidWakeNotification`, `sessionDidResignActiveNotification`, and `sessionDidBecomeActiveNotification`.
  - Coordinates clean suspension before sleep (clearing modifiers, cancelling in-flight timers, resetting gesture state machines).
- **Automated Event Tap Self-Healing**:
  - `EventTapManager` intercepts both `tapDisabledByTimeout` and `tapDisabledByUserInput`, automatically re-enabling `CGEventTap` without requiring app restart.
  - Implements `ensureTapActive()` health checks on wake and resume.
- **Staged Bluetooth Re-Diversion**:
  - On wake, `HIDPlusPlusManager` discards stale IOHID handles and restarts device matching.
  - Executes staged re-diversion passes at **+1.5s** and **+3.0s** to seamlessly re-apply `setCidReporting` once the Bluetooth radio link completes its OS handshake.
  - Hardware transmission errors automatically trigger stale-handle recovery.
- **Menu Bar Resume Sync**:
  - Toggling "Resume Gestures" in the menu bar executes an explicit health check and hardware re-initialization.

### M. SwiftUI Native Preferences Window & Keycode Resolver
- **Visual Preferences Window (`PreferencesWindowController`)**:
  - Pure macOS 13+ native SwiftUI interface accessed via **Preferences...** (`⌘,`) from the menu bar status item.
  - Multi-tab organization:
    1. **Gestures**: Cardinal swipe cards (Left, Right, Up, Down) and Thumb Click with directional icons, explanations, and instant action assignment.
    2. **Side Buttons**: Back & Forward button hardware index configuration and custom action / universal navigation diversion.
    3. **App Profiles**: Master-detail per-application override manager with macOS Application bundle selection (`/Applications`), dynamic prefix matching, and inheritance toggles.
    4. **General & Tuning**: Interactive sensitivity sliders (`ThresholdDistance`, `DeadzoneRadius`, `GestureWindowMs`, `SwallowTriggerEvents`) with human-friendly descriptions, startup login items, menu bar visibility, log level pickers, and permission status badges.
    5. **Live Tester**: Real-time calibration canvas featuring button state badges, cursor displacement vectors, deadzone and threshold rings, and live gesture direction detection.
- **Dynamic Keyboard Layout & KeyCode Resolver (`KeyCodeHelper`)**:
  - Resolves macOS physical `CGKeyCode` to characters using Carbon `TISCopyCurrentKeyboardInputSource` and `UCKeyTranslate`, correctly displaying the active keyboard layout (QWERTY, AZERTY, Colemak, Turkish, etc.).
  - Normalizes special keys (Arrows `↑ ↓ ← →`, `Return ↩`, `Tab ⇥`, `Delete ⌫`, `Escape ⎋`, `Space`, `F1-F20`, `Home/End/PageUp/PageDown`) and macOS modifier glyphs (`⌃`, `⌥`, `⇧`, `⌘`).
  - Provides an interactive **Shortcut Recorder** (`ShortcutRecorderView`) allowing users to press any key combination without typing or searching for numeric keycodes.
- **Bidirectional Config Sync & Debounced Auto-Save**:
  - Changes in the UI auto-save to `~/.config/GestureDaemon/config.plist` using `PropertyListEncoder(outputFormat: .xml)`.
  - External edits to `config.plist` are detected by the DispatchSource file monitor and instantly propagate to the open preferences window.

---

## 2. Complete Configuration Guide (config.plist)

GestureDaemon is fully configuration-driven. Every button index, timing window, drag threshold, and directional action can be customized to suit individual workflows.

### Configuration Locations & Priority

When GestureDaemon starts, it searches for configuration files in this order:

1. **`~/.config/GestureDaemon/config.plist`** (Primary user configuration)
2. **`~/Library/Application Support/GestureDaemon/config.plist`** (Standard macOS fallback)
3. **Bundled Fallback (`default_config.plist`)**: If neither file exists, GestureDaemon automatically generates `~/.config/GestureDaemon/config.plist` with default settings and locks POSIX permissions to `0600`.

To quickly edit your active configuration, click the menu bar icon and choose **Open Configuration File...**, or edit it directly in terminal:

```bash
open -e ~/.config/GestureDaemon/config.plist
# Or using your favorite terminal editor:
nano ~/.config/GestureDaemon/config.plist
```

### Live Hot-Reloading

GestureDaemon utilizes a Grand Central Dispatch file descriptor monitor (`DispatchSource.makeFileSystemObjectSource` with `[.write, .rename, .delete]`).
**You do not need to restart the application when modifying settings.** The moment you save `config.plist`, GestureDaemon reloads and applies the new configuration in real time.

---

### Configuration Schema & Parameter Reference

Below is the annotated XML schema for `config.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Physical mouse button index for gestures (Buttons 3, 4, 5, etc.) -->
    <key>TriggerButtonIndex</key>
    <integer>5</integer>

    <!-- Distance in points the cursor must move to register a flick (Default: 35.0) -->
    <key>ThresholdDistance</key>
    <real>35.0</real>

    <!-- Deadzone radius in points to ignore minor jitter before starting a drag (Default: 8.0) -->
    <key>DeadzoneRadius</key>
    <real>8.0</real>

    <!-- Duration in milliseconds to wait for a flick before triggering a stationary click (Default: 75.0) -->
    <key>GestureWindowMs</key>
    <real>75.0</real>

    <!-- Whether to display the icon in the macOS menu bar (Default: true) -->
    <key>ShowMenuBarIcon</key>
    <true/>

    <!-- Whether to prevent the trigger button from passing through to foreground apps (Default: true) -->
    <key>SwallowTriggerEvents</key>
    <true/>

    <!-- Enable system-wide side navigation buttons (Back / Forward) -->
    <key>EnableSideButtons</key>
    <true/>

    <!-- Hardware button index for Back (Default: 3) -->
    <key>BackButtonIndex</key>
    <integer>3</integer>

    <!-- Hardware button index for Forward (Default: 4) -->
    <key>ForwardButtonIndex</key>
    <integer>4</integer>

    <!-- Whether to enable diagnostic file logging to ~/.config/GestureDaemon/daemon.log (Default: false) -->
    <key>EnableLogging</key>
    <false/>

    <!-- Diagnostic log level: "Debug", "Info", "Error", "None" (Default: "Info") -->
    <key>LogLevel</key>
    <string>Info</string>

    <!-- Optional custom action for Back button (omitted = smart navigation back: Cmd+[ / VS Code Ctrl+-) -->
    <!-- <key>BackButtonAction</key><dict> ... </dict> -->

    <!-- Optional custom action for Forward button (omitted = smart navigation forward: Cmd+] / VS Code Ctrl+Shift+-) -->
    <!-- <key>ForwardButtonAction</key><dict> ... </dict> -->

    <!-- Base Actions (Executed when not overridden by Applications profiles) -->
    <!-- Click: Mission Control (Native CoreDock Notification) -->
    <key>ClickAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>126</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Mission Control</string>
    </dict>
    <!-- Drag Left: Space Right -->
    <key>DragLeftAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>124</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Switch to Space Right</string>
    </dict>
    <!-- Drag Right: Space Left -->
    <key>DragRightAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>123</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Switch to Space Left</string>
    </dict>
    <!-- Drag Up: Mission Control -->
    <key>DragUpAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>126</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>Mission Control</string>
    </dict>
    <!-- Drag Down: App Exposé (Native CoreDock Notification) -->
    <key>DragDownAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>125</integer>
        <key>Modifiers</key><array><string>Control</string></array>
        <key>Comment</key><string>App Exposé</string>
    </dict>

    <!-- Per-Application Contextual Overrides -->
    <key>Applications</key>
    <dict>
        <!-- Visual Studio Code: Dynamic history navigation via code: Equal (KeyCode 24) -->
        <key>com.microsoft.VSCode</key>
        <dict>
            <key>BackButtonAction</key>
            <dict>
                <key>Type</key><string>Shortcut</string>
                <key>KeyCode</key><integer>24</integer>
                <key>Modifiers</key><array><string>Control</string></array>
            </dict>
            <key>ForwardButtonAction</key>
            <dict>
                <key>Type</key><string>Shortcut</string>
                <key>KeyCode</key><integer>24</integer>
                <key>Modifiers</key><array><string>Control</string><string>Shift</string></array>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
```

#### Parameter Details

| Key | Type | Default | Description |
|---|---|---|---|
| `TriggerButtonIndex` | Integer | `5` | Quartz mouse button index used as the gesture trigger (typically `5` for M720 thumb button). For standard thumb buttons, try `3` (Back) or `4` (Forward). Run `GestureDaemon --diagnostics` to view hardware indices. |
| `ThresholdDistance` | Real | `35.0` | Minimum cursor travel (in screen points) required to trigger a directional swipe. Increase for stiffer gestures; decrease for effortless flicks. |
| `DeadzoneRadius` | Real | `8.0` | Radius around the starting point where movement is ignored. Prevents hand tremor from turning a stationary click into an accidental swipe. |
| `GestureWindowMs` | Real | `75.0` | Evaluation window in milliseconds. If the button is released or remains stationary within this window, `ClickAction` fires. If swiped beyond `ThresholdDistance` within this window, the corresponding directional action fires immediately. |
| `ShowMenuBarIcon` | Boolean | `true` | When `true`, displays the status icon in the macOS menu bar. When `false`, runs headlessly in the background. |
| `SwallowTriggerEvents`| Boolean | `true` | When `true`, prevents the underlying button press from reaching the frontmost application. |
| `EnableSideButtons` | Boolean | `true` | When `true`, intercepts mouse side buttons and converts them to navigation actions. |
| `BackButtonIndex` | Integer | `3` | Button index representing the physical Back button (default `3`). |
| `ForwardButtonIndex` | Integer | `4` | Button index representing the physical Forward button (default `4`). |
| `BackButtonAction` | Dictionary | *Smart Back* | Custom action for Back button. If omitted, uses intelligent Back (`Cmd + [` in browsers/Finder, `Ctrl + -` in VS Code). |
| `ForwardButtonAction` | Dictionary | *Smart Forward* | Custom action for Forward button. If omitted, uses intelligent Forward (`Cmd + ]` in browsers/Finder, `Ctrl + Shift + -` in VS Code). |

---

### Action Types & Syntax

Every gesture slot (`ClickAction`, `DragLeftAction`, `DragRightAction`, `DragUpAction`, `DragDownAction`) accepts one of three action types:

#### 1. Shortcut (`Type = Shortcut`)
Sends simulated keystrokes to the system or invokes native macOS WindowServer / Dock actions.

```xml
<dict>
    <key>Type</key><string>Shortcut</string>
    <key>KeyCode</key><integer>124</integer>
    <key>Modifiers</key>
    <array>
        <string>Control</string>
    </array>
</dict>
```

*Supported Modifiers*: `"Control"`, `"Command"`, `"Option"`, `"Shift"`.

##### Built-in Optimized System Shortcuts:
When configured with modifier `["Control"]`, the following keycodes leverage high-speed native system SPI rather than synthetic keyboard events:
- **`KeyCode 126` (Ctrl + Up)**: Mission Control (`CoreDockSendNotification`)
- **`KeyCode 125` (Ctrl + Down)**: App Exposé (`CoreDockSendNotification`)
- **`KeyCode 123` (Ctrl + Left)**: Move Left a Space (Native CGS HotKey `79`)
- **`KeyCode 124` (Ctrl + Right)**: Move Right a Space (Native CGS HotKey `81`)

#### 2. Application (`Type = Application`)
Launches or brings to focus an installed macOS application using its bundle identifier.

```xml
<dict>
    <key>Type</key><string>Application</string>
    <key>BundleIdentifier</key><string>com.apple.Terminal</string>
</dict>
```

#### 3. Command (`Type = Command`)
Executes an arbitrary shell command or script using `/bin/zsh -c`.

```xml
<dict>
    <key>Type</key><string>Command</string>
    <key>CommandPath</key><string>osascript -e 'set volume output muted not (output muted of (get volume settings))'</string>
</dict>
```

---

### Virtual KeyCode Reference Table

For custom shortcuts, refer to standard macOS virtual keycodes:

| Key | Virtual KeyCode | Key | Virtual KeyCode |
|---|---|---|---|
| **Arrow Left** | `123` | **Return / Enter** | `36` |
| **Arrow Right** | `124` | **Tab** | `48` |
| **Arrow Down** | `125` | **Space** | `49` |
| **Arrow Up** | `126` | **Escape** | `53` |
| **A** | `0` | **Delete (Backspace)** | `51` |
| **S** | `1` | **Forward Delete** | `117` |
| **D** | `2` | **Home** | `115` |
| **W** | `13` | **End** | `119` |
| **Q** | `12` | **Page Up** | `116` |
| **Z** | `6` | **Page Down** | `121` |
| **C** | `8` | **F1** | `122` |
| **V** | `9` | **F2** | `120` |
| **T** | `17` | **F11** | `103` |
| **R** | `15` | **F12** | `111` |
| **Minus / Underscore (US ANSI)** | `27` | **Equal / Plus (US ANSI)** | `24` |

> [!TIP]
> **Hardware KeyCodes vs. International Keyboard Layouts**:
> macOS virtual keycodes represent the **physical position** on a standard US ANSI keyboard.
> On localized layouts such as **Turkish Q**, the characters on the top row are rearranged:
> - **KeyCode 27** (physical switch right of `0`) produces `*` / `?`.
> - **KeyCode 24** (physical switch between `27` and Delete) produces **`-`** / **`_`**!
> 
> Therefore, if you are configuring a shortcut for the `-` key on a Turkish Q layout (e.g. for VS Code navigation), use **`KeyCode 24`** (`kVK_ANSI_Equal`) because your finger physically presses switch #24 to type `-`.

---

### Real-World Configuration Recipes

#### Recipe 1: Default macOS Power User (Spaces & Exposé)
*Natural gestures: Flick left to go right, flick right to go left, click for Mission Control, flick down for App Exposé.*

```xml
<dict>
    <key>TriggerButtonIndex</key><integer>5</integer>
    <key>ThresholdDistance</key><real>35.0</real>
    <key>DeadzoneRadius</key><real>8.0</real>
    <key>GestureWindowMs</key><real>75.0</real>
    <key>ShowMenuBarIcon</key><true/>
    <key>SwallowTriggerEvents</key><true/>

    <!-- Click: Mission Control -->
    <key>ClickAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>126</integer>
        <key>Modifiers</key><array><string>Control</string></array>
    </dict>

    <!-- Drag Left: Switch to Right Space -->
    <key>DragLeftAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>124</integer>
        <key>Modifiers</key><array><string>Control</string></array>
    </dict>

    <!-- Drag Right: Switch to Left Space -->
    <key>DragRightAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>123</integer>
        <key>Modifiers</key><array><string>Control</string></array>
    </dict>

    <!-- Drag Down: App Exposé -->
    <key>DragDownAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>125</integer>
        <key>Modifiers</key><array><string>Control</string></array>
    </dict>
</dict>
```

#### Recipe 2: Developer & Productivity Workflow
*Click to launch/focus iTerm2, Drag Left to cycle previous window (Cmd+`), Drag Right to cycle next window, Drag Up to open VS Code.*

```xml
<dict>
    <key>TriggerButtonIndex</key><integer>5</integer>
    <key>ThresholdDistance</key><real>40.0</real>
    <key>GestureWindowMs</key><real>200.0</real>

    <!-- Click: Launch / Focus Terminal -->
    <key>ClickAction</key>
    <dict>
        <key>Type</key><string>Application</string>
        <key>BundleIdentifier</key><string>com.googlecode.iterm2</string>
    </dict>

    <!-- Drag Up: Launch / Focus Visual Studio Code -->
    <key>DragUpAction</key>
    <dict>
        <key>Type</key><string>Application</string>
        <key>BundleIdentifier</key><string>com.microsoft.VSCode</string>
    </dict>

    <!-- Drag Left: Previous Tab in Editors (Cmd+Shift+[) -->
    <key>DragLeftAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>33</integer>
        <key>Modifiers</key><array><string>Command</string><string>Shift</string></array>
    </dict>

    <!-- Drag Right: Next Tab in Editors (Cmd+Shift+]) -->
    <key>DragRightAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>30</integer>
        <key>Modifiers</key><array><string>Command</string><string>Shift</string></array>
    </dict>
</dict>
```

#### Recipe 3: Web Browsing & Media Controls
*Click to Toggle Audio Mute, Drag Left for Browser Back (Cmd+[), Drag Right for Browser Forward (Cmd+]).*

```xml
<dict>
    <key>TriggerButtonIndex</key><integer>5</integer>
    <key>ThresholdDistance</key><real>30.0</real>

    <!-- Click: Toggle Audio Mute via AppleScript -->
    <key>ClickAction</key>
    <dict>
        <key>Type</key><string>Command</string>
        <key>CommandPath</key><string>osascript -e 'set volume output muted not (output muted of (get volume settings))'</string>
    </dict>

    <!-- Drag Left: Back (Cmd + [) -->
    <key>DragLeftAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>33</integer>
        <key>Modifiers</key><array><string>Command</string></array>
    </dict>

    <!-- Drag Right: Forward (Cmd + ]) -->
    <key>DragRightAction</key>
    <dict>
        <key>Type</key><string>Shortcut</string>
        <key>KeyCode</key><integer>30</integer>
        <key>Modifiers</key><array><string>Command</string></array>
    </dict>
</dict>
```

---

### Per-Application Contextual Profiles (`Applications`)

GestureDaemon allows you to define application-specific overrides under the `<key>Applications</key>` dictionary. When an application becomes frontmost, GestureDaemon automatically switches to that app's profile with **zero latency** ($O(1)$ memory lookup via cached `NSWorkspace.didActivateApplicationNotification`).

Any action omitted in an app profile gracefully falls back to your global configuration.

#### How to Find Any App's Bundle Identifier
Run this command in Terminal to print the bundle ID of any installed app:
```bash
osascript -e 'id of app "Safari"'        # Returns: com.apple.Safari
osascript -e 'id of app "Visual Studio Code"' # Returns: com.microsoft.VSCode
osascript -e 'id of app "Google Chrome"' # Returns: com.google.Chrome
osascript -e 'id of app "Finder"'        # Returns: com.apple.finder
```

#### Example Configuration: Safari & Final Cut Pro Overrides
Add this to your `~/.config/GestureDaemon/config.plist`:

```xml
<key>Applications</key>
<dict>
    <!-- Safari: Flick Left/Right cycles tabs instead of switching desktop spaces -->
    <key>com.apple.Safari</key>
    <dict>
        <!-- Drag Left: Previous Tab (Cmd+Shift+[) -->
        <key>DragLeftAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>33</integer>
            <key>Modifiers</key><array><string>Command</string><string>Shift</string></array>
            <key>Comment</key><string>Previous Tab</string>
        </dict>

        <!-- Drag Right: Next Tab (Cmd+Shift+]) -->
        <key>DragRightAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>30</integer>
            <key>Modifiers</key><array><string>Command</string><string>Shift</string></array>
            <key>Comment</key><string>Next Tab</string>
        </dict>
    </dict>

    <!-- Visual Studio Code: Map thumb button click to Toggle Terminal -->
    <key>com.microsoft.VSCode</key>
    <dict>
        <key>ClickAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>50</integer>
            <key>Modifiers</key><array><string>Control</string></array>
            <key>Comment</key><string>Toggle Terminal (Ctrl+`)</string>
        </dict>
    </dict>
</dict>
```

---

## 3. Future Roadmap (What We Can Do Next)

While GestureDaemon now provides full dual-transport (USB Unifying/Bolt & direct Bluetooth Low Energy) HID++ hardware button diversion and gesture switching without the battery and CPU penalties, here are the next capabilities on our roadmap:

### 1. Diagonal & 8-Way Gesture Recognition
- **Concept**: Expand from 4 cardinal directions (Left, Right, Up, Down) to 8 directions by evaluating the angle $\theta = \operatorname{atan2}(\Delta y, \Delta x)$:
  - `DragUpLeftAction`
  - `DragUpRightAction`
  - `DragDownLeftAction`
  - `DragDownRightAction`
- Gives power users 8 distinct gesture actions on a single thumb button.

### 2. Haptic Feedback Integration
- **Concept**: Provide physical sensory confirmation when a gesture threshold is reached.
- **Implementation**:
  - For MacBook users, trigger the trackpad's Force Touch Taptic Engine using `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`.
  - For supported mice with internal haptic actuators (e.g. MX Master 4), send the HID++ 2.0 haptic pulse command over the receiver report pipe when `distance >= ThresholdDistance`.

### 3. Developer ID Signing & Notarization Pipeline
- **Concept**: Prepare the application for public distribution outside local machines without triggering macOS Gatekeeper warnings.
- **Implementation**:
  - Add `notarize` target to `Makefile` using `xcrun notarytool submit build/GestureDaemon.dmg --keychain-profile ... --wait`.
  - Staple the notarization ticket to the disk image using `xcrun stapler staple build/GestureDaemon.dmg`.

---

## 4. Summary

GestureDaemon demonstrates that high-performance macOS utilities do not require multi-gigabyte Electron runtimes, background telemetry daemons, or heavy proprietary suites. By pairing clean Swift architecture with direct macOS SPI and ephemeral resource management, GestureDaemon delivers instant responsiveness, absolute privacy, and true 0.0% idle system impact.

