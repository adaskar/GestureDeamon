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
2. [Complete Configuration Guide (config.plist)](#2-complete-configuration-guide-configplist)
   - [Configuration Locations & Priority](#configuration-locations--priority)
   - [Live Hot-Reloading](#live-hot-reloading)
   - [Configuration Schema & Parameter Reference](#configuration-schema--parameter-reference)
   - [Action Types & Syntax](#action-types--syntax)
   - [Virtual KeyCode Reference Table](#virtual-keycode-reference-table)
   - [Real-World Configuration Recipes](#real-world-configuration-recipes)
3. [Future Roadmap (What We Can Do Next)](#3-future-roadmap-what-we-can-do-next)
   - [Direct Bluetooth LE HID++ Support](#1-direct-bluetooth-le-hid-support)
   - [Per-Application Contextual Profiles](#2-per-application-contextual-profiles)
   - [Diagonal & 8-Way Gesture Recognition](#3-diagonal--8-way-gesture-recognition)
   - [Haptic Feedback Integration](#4-haptic-feedback-integration)
   - [SwiftUI Native Preferences Window](#5-swiftui-native-preferences-window)
   - [Developer ID Signing & Notarization Pipeline](#6-developer-id-signing--notarization-pipeline)

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
- **Latency Optimization**: Reduced the gesture evaluation window from `400ms` to **`200ms`**, making single clicks feel snappy and instantaneous while preserving reliable flick detection.

### F. Zero-Overhead Ephemeral Dynamic Motion Tap (0.0% CPU)
- **Root Cause of Previous CPU Spikes**:
  - In CoreGraphics, calling `CGEvent.tapEnable(tap, false)` notifies the tap callback with `kCGEventTapDisabledByUserInput`. The original code treated this as an unexpected error and automatically re-enabled the tap.
  - This caused a persistent `mouseMoved` tap to run constantly. Touchpads emit 120–240 sub-pixel events per second on ProMotion displays, forcing `WindowServer` to perform hundreds of synchronous Mach IPC context switches into `GestureDaemon` every second.
- **The Ephemeral Lifecycle Solution**:
  - At daemon startup, **no motion tap exists** (`motionEventTap = nil`). `primaryEventTap` strictly listens to button clicks, keys, and modifier changes.
  - When the user presses the gesture trigger, `startMotionTap()` creates the `mouseMoved` tap dynamically for the duration of the 200ms window.
  - As soon as the swipe threshold is crossed or the stationary click timer expires, `stopMotionTap()` calls `CFMachPortInvalidate(tap)` and removes the run loop source, unregistering the tap from `WindowServer`.
  - **Result**: Moving the trackpad or mouse during normal operation produces **zero Mach messages, zero context switches, and steady 0.0% CPU**.

### G. Standard macOS DMG Packaging
- Created `scripts/create_dmg.sh` and `make dmg` targets to generate `build/GestureDaemon.dmg` with an embedded `/Applications` drag-and-drop symlink and custom multi-resolution icon (`AppIcon.icns`).

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

    <!-- Duration in milliseconds to wait for a flick before triggering a stationary click (Default: 200.0) -->
    <key>GestureWindowMs</key>
    <real>200.0</real>

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

    <!-- Optional custom action for Back button (omitted = smart navigation back: Cmd+[ / VS Code Ctrl+-) -->
    <!-- <key>BackButtonAction</key><dict> ... </dict> -->

    <!-- Optional custom action for Forward button (omitted = smart navigation forward: Cmd+] / VS Code Ctrl+Shift+-) -->
    <!-- <key>ForwardButtonAction</key><dict> ... </dict> -->

    <!-- Action executed on a stationary click (no drag) -->
    <key>ClickAction</key>
    <dict> ... </dict>

    <!-- Action executed on a flick to the left -->
    <key>DragLeftAction</key>
    <dict> ... </dict>

    <!-- Action executed on a flick to the right -->
    <key>DragRightAction</key>
    <dict> ... </dict>

    <!-- Action executed on a flick upwards -->
    <key>DragUpAction</key>
    <dict> ... </dict>

    <!-- Action executed on a flick downwards -->
    <key>DragDownAction</key>
    <dict> ... </dict>
</dict>
</plist>
```

#### Parameter Details

| Key | Type | Default | Description |
|---|---|---|---|
| `TriggerButtonIndex` | Integer | `5` | Quartz mouse button index used as the gesture trigger (typically `5` for M720 thumb button). For standard thumb buttons, try `3` (Back) or `4` (Forward). Run `GestureDaemon --diagnostics` to view hardware indices. |
| `ThresholdDistance` | Real | `35.0` | Minimum cursor travel (in screen points) required to trigger a directional swipe. Increase for stiffer gestures; decrease for effortless flicks. |
| `DeadzoneRadius` | Real | `8.0` | Radius around the starting point where movement is ignored. Prevents hand tremor from turning a stationary click into an accidental swipe. |
| `GestureWindowMs` | Real | `200.0` | Evaluation window in milliseconds. If the button is released or remains stationary within this window, `ClickAction` fires. If swiped beyond `ThresholdDistance` within this window, the corresponding directional action fires immediately. |
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

---

### Real-World Configuration Recipes

#### Recipe 1: Default macOS Power User (Spaces & Exposé)
*Natural gestures: Flick left to go right, flick right to go left, click for Mission Control, flick down for App Exposé.*

```xml
<dict>
    <key>TriggerButtonIndex</key><integer>5</integer>
    <key>ThresholdDistance</key><real>35.0</real>
    <key>DeadzoneRadius</key><real>8.0</real>
    <key>GestureWindowMs</key><real>200.0</real>
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

While GestureDaemon currently provides full feature parity with Logitech Options+ gesture switching without the battery and CPU penalties, here are the most impactful capabilities on our roadmap:

### 1. Direct Bluetooth LE HID++ Support
- **Current State**: `HIDPlusPlusManager` currently listens via `IOHIDManager` for USB receivers (Vendor ID `0x046d`, Usage Page `0xFF00`). When connected over Bluetooth, Logitech mice default to standard HID descriptor emulation and send the thumb button via the fallback keyboard macro (`Cmd+Option+Tab`).
- **Improvement**: Implement direct Bluetooth HID++ parsing using `IOBluetooth` / `CoreBluetooth` or custom L2CAP channel listening. This would allow reading battery levels, setting DPI on the fly, and toggling SmartShift ratchet mode directly over Bluetooth without requiring a USB Unifying/Bolt receiver.

### 2. Per-Application Contextual Profiles (Completed in v1.2)
- ✅ Implemented via `NSWorkspace.didActivateApplicationNotification` and `<key>Applications</key>` dictionary with hierarchical action resolution.

### 3. Diagonal & 8-Way Gesture Recognition
- **Concept**: Expand from 4 cardinal directions (Left, Right, Up, Down) to 8 directions by evaluating the angle $\theta = \operatorname{atan2}(\Delta y, \Delta x)$:
  - `DragUpLeftAction`
  - `DragUpRightAction`
  - `DragDownLeftAction`
  - `DragDownRightAction`
- Gives power users 8 distinct gesture actions on a single thumb button.

### 4. Haptic Feedback Integration
- **Concept**: Provide physical sensory confirmation when a gesture threshold is reached.
- **Implementation**:
  - For MacBook users, trigger the trackpad's Force Touch Taptic Engine using `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`.
  - For supported mice with internal haptic actuators (e.g. MX Master 4), send the HID++ 2.0 haptic pulse command over the receiver report pipe when `distance >= ThresholdDistance`.

### 5. SwiftUI Native Preferences Window
- **Concept**: A modern, clean settings window accessed from the menu bar ("Preferences...") for users who prefer visual configuration over raw plist editing.
- **Architecture**:
  - Built with pure SwiftUI (`Settings` or `NSWindowController`).
  - Reads and writes to the existing `config.plist` model, maintaining full compatibility with the CLI and live file watcher.
  - Interactive keycode recorder and button tester.

### 6. Developer ID Signing & Notarization Pipeline
- **Concept**: Prepare the application for public distribution outside local machines without triggering macOS Gatekeeper warnings.
- **Implementation**:
  - Add `notarize` target to `Makefile` using `xcrun notarytool submit build/GestureDaemon.dmg --keychain-profile ... --wait`.
  - Staple the notarization ticket to the disk image using `xcrun stapler staple build/GestureDaemon.dmg`.

---

## 4. Summary

GestureDaemon demonstrates that high-performance macOS utilities do not require multi-gigabyte Electron runtimes, background telemetry daemons, or heavy proprietary suites. By pairing clean Swift architecture with direct macOS SPI and ephemeral resource management, GestureDaemon delivers instant responsiveness, absolute privacy, and true 0.0% idle system impact.

