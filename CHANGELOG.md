# Changelog

All notable changes to **GestureDaemon** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.1] - 2026-09-19

### 🚀 Initial Public Release

GestureDaemon is a lightweight, zero-telemetry, zero-dependency native macOS daemon and menu bar utility engineered to replace heavy mouse suites (like Logitech Options+) for multi-button mice including the Logitech M720 Triathlon, MX Master series, and standard 5-button mice.

#### ✨ Key Features

- **⚡️ True 0.0% Idle CPU**: Ephemeral event-tap lifecycle guarantees zero IPC wakeups and zero context switches during normal mouse and trackpad motion.
- **🪟 Instant macOS Spaces & Mission Control Switching**: Native integration via WindowServer private Symbolic HotKeys and CGS SPI with `NX_SECONDARYFNMASK` modifier injection.
- **🎯 Native Dock Integration**: Instant Mission Control and App Exposé via private `CoreDockSendNotification`.
- **🔊 Thumb Gesture + Scroll Wheel Chording**: Hold the thumb button and scroll the wheel to trigger native macOS HUD volume adjustment, cleanly swallowing scroll events to prevent page jumping.
- **📡 Dual-Transport HID++ 2.0 Diversion**: Automatic hardware button diversion over both USB Unifying/Bolt receivers (`0xFF00`) and direct Bluetooth Low Energy (`0xFF43:0x0202`).
- **🔋 Live Mouse Battery Telemetry**: Queries battery level and charging status via native HID++ (`0x1000`/`0x1004`) directly in the macOS menu bar.
- **🧭 Universal Side Navigation (Buttons 3 & 4)**: Back and Forward history navigation (`Cmd+[` / `Cmd+]`) across Safari, Chrome, and Finder, with IDE navigation (`Ctrl+-` / `Ctrl+Shift+-`) in Visual Studio Code.
- **🎛 Full SwiftUI Preferences Window (`⌘,`)**:
  - **Gestures**: Configurable actions for Up, Down, Left, Right gestures and single thumb press.
  - **Side Buttons**: Dedicated button 3/4 assignments and mode overrides.
  - **App Profiles**: Contextual per-application custom gesture and button overrides.
  - **General & Tuning**: Sliders for distance threshold, gesture window, deadzone, scroll rate limit, and menu bar icon styles.
  - **Live Calibration Tester**: Interactive visual canvas displaying cursor displacement vectors, threshold boundaries, and real-time gesture recognition.
- **⌨️ Interactive Shortcut Recorder**: Capture custom shortcuts with automatic layout normalization across international keyboards.
- **📱 Per-Application Contextual Profiles**: Context-aware gesture and button behaviors that switch automatically based on the active frontmost app.
- **🌙 Power & Sleep/Wake Resilience**: Self-healing `SleepWakeManager` that detects system sleep, screen lock, and display changes, automatically re-attaching event taps and re-diverting hardware buttons upon wake.
- **🍏 Modern macOS Agent Architecture**: Bundled `.app` with `LSUIElement=true`, status bar controller, customizable menu bar styles ("standard", "battery", "batteryWithPercentage", "hidden"), headless reopen recovery, and `SMAppService` launch-at-login integration.
- **🏗 Universal Binary**: Single native binary supporting both Apple Silicon (M1/M2/M3/M4) and Intel (x86_64) Macs on macOS 13.0 (Ventura) and later.

#### ⚠️ Gatekeeper & First-Launch Authorization (Not Notarized)

Because GestureDaemon is an open-source utility distributed without an Apple Developer ID subscription ($99/yr), the pre-compiled application is ad-hoc signed and **not notarized by Apple**. When downloaded via a web browser, macOS Gatekeeper will place it in quarantine by default.

To open the app on macOS Ventura, Sonoma, Sequoia, or later, use either method:

- **Option A — System Settings (GUI)**:
  1. Attempt to open `GestureDaemon.app` once from `/Applications` (macOS will show a security prompt; click **Done** or **Cancel**).
  2. Open **System Settings** → **Privacy & Security**.
  3. Scroll down to the **Security** section where you will see: *"GestureDaemon.app was blocked from use because it is not from an identified developer"*.
  4. Click **"Open Anyway"** and authenticate with your password or Touch ID.

- **Option B — Terminal Quick-Fix (`xattr`)**:
  Remove the macOS quarantine attribute directly:
  ```bash
  xattr -cr /Applications/GestureDaemon.app
  ```
  Then launch normally:
  ```bash
  open /Applications/GestureDaemon.app
  ```

