# GestureDaemon 🪟🖱️

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square&logo=swift)](https://developer.apple.com/swift/)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-blue?style=flat-square)](https://developer.apple.com)
[![CPU Usage](https://img.shields.io/badge/Idle%20CPU-0.0%25-brightgreen?style=flat-square)](https://github.com)
[![Dependencies](https://img.shields.io/badge/Dependencies-Zero-success?style=flat-square)](https://github.com)
[![License](https://img.shields.io/badge/License-MIT-purple?style=flat-square)](LICENSE)

> **Ultra-lightweight, zero-telemetry native macOS background daemon and menu bar utility replacing Logitech Options+ for multi-button mice.**

Built in 100% pure Swift with **zero external dependencies**. Consumes **0.0% idle CPU** and less than 15 MB of RAM while delivering instant, sub-millisecond Mission Control, App Exposé, Spaces navigation, and universal side-button history controls.

---

## 💡 Why GestureDaemon?

Proprietary mouse suites (such as Logitech Options+ / Logi G HUB) run multi-gigabyte Electron runtimes, background analytics daemons, network telemetry agents, and consume significant CPU and battery life just to intercept a couple of thumb buttons.

**GestureDaemon** replaces the entire bloatware stack with a tiny, standalone native binary (~2 MB):

| Metric | Logitech Options+ | GestureDaemon |
|---|---|---|
| **Idle CPU Usage** | 1% – 5% (constant wakeups) | **0.0%** (zero IPC wakeups) |
| **Memory Footprint** | 300 MB – 800 MB+ | **< 15 MB** |
| **Dependencies / Runtimes** | Node.js, Electron, Python, Crashpad | **Zero** (Pure Swift & Apple SPI) |
| **Network Telemetry** | Active tracking & analytics | **100% Offline & Private** |
| **Configuration** | Heavy cloud-synced GUI | Clean XML/Plist with **Live Hot-Reloading** |
| **Space Transitions** | Emulated keys (frequent escape codes) | Native WindowServer Symbolic HotKeys |

---

## ✨ Features

- ⚡️ **True 0.0% Idle CPU**: Ephemeral event-tap lifecycle guarantees zero IPC wakeups and zero context switches during normal mouse and trackpad pointer motion.
- 🪟 **Fluid Spaces & Mission Control Transitions**: Uses reverse-engineered Apple CoreGraphics Services (CGS) SPI with `NX_SECONDARYFNMASK` modifier injection for flawless native Desktop switching.
- 🎯 **Native Dock Integration**: Instant Mission Control and App Exposé via private `CoreDockSendNotification`.
- 🧼 **Modifier Sanitization**: Unconditionally swallows Logitech's hardware fallback `Cmd+Option+Tab` thumb macro and flushes system modifiers—preventing VS Code or browser tab bars from stealing focus.
- 🧭 **Universal Side Navigation (Back & Forward)**: Translates side buttons (Buttons 3 & 4) into instant history navigation (`Cmd+[` / `Cmd+]`) across Safari, Chrome, and Finder, with smart IDE navigation (`Ctrl+-` / `Ctrl+Shift+-`) in Visual Studio Code.
- 📱 **Per-Application Contextual Profiles**: Dynamically override gestures and button bindings based on the active foreground application (e.g. scrub timelines in video editors, navigate history in browsers, toggle terminal in IDEs).
- 🎛 **Live Hot-Reloading (`config.plist`)**: Edit your configuration in `~/.config/GestureDaemon/config.plist` and changes take effect immediately without restarting.
- 🍏 **Modern macOS Agent**: Native `.app` bundle with `LSUIElement=true`, status bar controller (`NSStatusItem`), "Hide Menu Bar Icon" mode with single-instance reopen recovery, and modern `SMAppService` launch-at-login integration.
- 🪵 **Built-in Diagnostic Logging**: Real-time event tracking and live logging at `~/.config/GestureDaemon/daemon.log` for easy troubleshooting.

---

## 🚀 Installation

### Option 1: Drag-and-Drop Disk Image (Recommended)

1. Download the latest release: **`GestureDaemon.dmg`**.
2. Double-click the DMG and drag **GestureDaemon.app** into your `/Applications` folder.
3. Open **GestureDaemon** from Applications or Spotlight.
4. When prompted, grant Accessibility in **System Settings → Privacy & Security → Accessibility**.
5. Click the menu bar icon to toggle **Launch at Login**.

### Option 2: Build From Source

```bash
# Clone the repository
git clone https://github.com/guru/GestureDaemon.git
cd GestureDaemon

# Build universal fat binary (arm64 + x86_64) and pack app bundle
make app

# Install directly to /Applications and launch
make install
```

To create a distributable disk image:
```bash
make dmg
# Result: build/GestureDaemon.dmg
```

---

## 🎮 Default Controls & Gestures

Optimized out-of-the-box for multi-button mice including the **Logitech M720 Triathlon**, **MX Master 2S / 3 / 3S**, and standard 5-button mice:

### 1. Thumb Button Gestures (Hold & Flick)

Hold the **Thumb Gesture Button** (or wrist-flick) and release:

```
                    ▲
             [ Mission Control ]
                    |
[ Space Right ] ◀── ● ──▶ [ Space Left ]
  (Drag Left)       |     (Drag Right)
                    ▼
              [ App Exposé ]
```

| Gesture Motion | Default Action | Technical Implementation |
|---|---|---|
| **Stationary Tap / Click** | **Mission Control** | `CoreDockSendNotification("com.apple.expose.awake")` |
| **Wrist-Flick Left** | **Switch to Right Space** | CGS Symbolic HotKey `81` (`Ctrl + Right`) |
| **Wrist-Flick Right** | **Switch to Left Space** | CGS Symbolic HotKey `79` (`Ctrl + Left`) |
| **Wrist-Flick Down** | **App Exposé** | `CoreDockSendNotification("com.apple.expose.front.awake")` |

*Timing: 200 ms evaluation window. Threshold: 35 pt. Deadzone: 8 pt.*

### 2. Side Navigation Buttons

| Physical Button | Button Index | Default Target Action |
|---|---|---|
| **Back Button** | `3` | **Navigate Back**: Browser / Finder (`Cmd + [`), VS Code (`Ctrl + -`) |
| **Forward Button** | `4` | **Navigate Forward**: Browser / Finder (`Cmd + ]`), VS Code (`Ctrl + Shift + -`) |

---

## ⚙️ Configuration

GestureDaemon stores your settings in a clean, human-readable property list at:
```bash
~/.config/GestureDaemon/config.plist
```

To edit it anytime, click the Menu Bar icon and select **Open Configuration File...**, or edit in your terminal:
```bash
open -e ~/.config/GestureDaemon/config.plist
```

> **Hot-Reloading**: GestureDaemon monitors the file descriptor. The millisecond you save changes, settings are applied live without needing to restart the daemon.

### Example: Per-Application Overrides

You can override gestures and buttons for specific applications using their bundle identifier:

```xml
<key>Applications</key>
<dict>
    <!-- Safari: Flick Left/Right cycles tabs instead of switching Spaces -->
    <key>com.apple.Safari</key>
    <dict>
        <key>DragLeftAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>33</integer>
            <key>Modifiers</key><array><string>Command</string><string>Shift</string></array>
            <key>Comment</key><string>Previous Tab (Cmd+Shift+[)</string>
        </dict>
        <key>DragRightAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>30</integer>
            <key>Modifiers</key><array><string>Command</string><string>Shift</string></array>
            <key>Comment</key><string>Next Tab (Cmd+Shift+])</string>
        </dict>
    </dict>

    <!-- Visual Studio Code: Back/Forward navigates editor history -->
    <key>com.microsoft.VSCode</key>
    <dict>
        <key>BackButtonAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>24</integer>
            <key>Modifiers</key><array><string>Control</string></array>
            <key>Comment</key><string>Navigate Back</string>
        </dict>
        <key>ForwardButtonAction</key>
        <dict>
            <key>Type</key><string>Shortcut</string>
            <key>KeyCode</key><integer>24</integer>
            <key>Modifiers</key><array><string>Control</string><string>Shift</string></array>
            <key>Comment</key><string>Navigate Forward</string>
        </dict>
    </dict>
</dict>
```

---

## 🔍 Diagnostics & Troubleshooting

GestureDaemon provides comprehensive live logging and a CLI diagnostic mode:

### 1. View Live Event Logs
Monitor button presses, frontmost application detections, and gesture resolutions in real-time:
```bash
tail -f ~/.config/GestureDaemon/daemon.log
```

### 2. Run Interactive Hardware Diagnostics
To inspect raw mouse button numbers and modifier keycodes from your physical hardware:
```bash
make diagnose
# Or directly:
/Applications/GestureDaemon.app/Contents/MacOS/GestureDaemon --diagnostics
```

### 3. Recover Hidden Menu Bar Icon
If you hid the status bar icon via "Hide Menu Bar Icon", simply launch **GestureDaemon** again from `/Applications` or Spotlight. The running daemon will wake up, temporarily restore the menu bar item, and display the menu.

---

## 📚 Complete Documentation

For complete architectural deep-dives, parameter dictionaries, virtual keycode lookup tables, and the upcoming feature roadmap, see:

📖 **[Full Architecture & Configuration Guide (DOCUMENTATION.md)](DOCUMENTATION.md)**

---

## 🤝 Contributing

Contributions, bug reports, and feature suggestions are welcome!
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
