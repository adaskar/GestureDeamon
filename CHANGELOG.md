# Changelog

All notable changes to **GestureDaemon** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-09-26

### 🚀 Production Release: General Availability

GestureDaemon 1.0.0 marks our first stable, production-ready release! This milestone delivers rock-solid hardware stability, complete Logitech Options+ feature parity with zero bloat, and refined battery telemetry.

### ✨ Added & Improved

- **🔋 Qualitative & Stepped Battery Telemetry Engine**:
  - **Accurate HID++ 2.0 Unified Battery (`0x1004`) Parsing** — Corrected packet parsing for byte 5 coarse levels (`Full`, `Good`, `Low`, `Critical`) and byte 6 charging status.
  - **Qualitative Health Normalization** — Resolved the confusion where Logitech Options showed *"Battery level is good"* while third-party apps showed an arbitrary `50%`. Devices reporting stepped voltage comparator tiers (such as the M720 Triathlon with AA battery or MX Master series) now display clean qualitative health (`Good`, `Full`, `Low`, `Critical`) across the menu bar, status dropdown, and Preferences.
  - **Eliminated macOS Bluetooth Discrepancy** — Harmonized presentation so that Logitech hardware status no longer contradicts macOS Bluetooth menu's uncalibrated GATT percentage.
  - **Centralized `displayText` Formatting** — Automatically chooses between qualitative state (`Good`) for stepped devices and granular percentages (`85%`) for fuel-gauge equipped hardware.
  - **Informative Preferences Tooltip** — Added helpful contextual explanations describing Logitech hardware voltage telemetry.

- **🖱️ Complete Smooth Scrolling Suite**:
  - Native CVDisplayLink 120 Hz / 60 Hz inertia engine with trackpad phase simulation (`scrollWheelEventScrollPhase` & momentum).
  - Configurable sensitivity, speed multiplier, deadzone, and inertia duration in Preferences.
  - Modifier quick-actions (`Option` 5× dash, `Shift` horizontal redirect, `Cmd` bypass).
  - Per-app bypass profiles for remote desktops (TeamViewer, Parsec, AnyDesk, Microsoft Remote Desktop).

- **🎛️ Full Native SwiftUI Preferences Window (`⌘,`)**:
  - 6 dedicated configuration tabs: Gestures, Side Buttons, App Profiles, Smooth Scrolling, General Hardware Tuning, and Live Calibration Tester Canvas.
  - Interactive international shortcut recorder with keyboard layout normalization.

- **⚡ Zero Bloat & Dual-Transport Architecture**:
  - True 0.0% idle CPU with ephemeral event-tap lifecycle.
  - Automatic hardware button diversion (`0x1B04` CID `0x00C3`) over both USB Unifying/Bolt receivers and direct Bluetooth Low Energy.
  - **Robust Staged Sleep / Wake Recovery Engine**:
    - Fixed an issue where gestures stopped responding after display sleep or system sleep until manually toggled in the menu bar.
    - Implemented a unified staged recovery pipeline ($t=0$, $+1.0s$, $+2.5s$, $+4.0s$) to re-issue hardware button diversion commands over Bluetooth LE once the radio link stabilizes after low-power sleep.
    - Updated `EventTapManager.ensureTapActive()` to detect invalidated Mach ports (`CFMachPortIsValid`) following sleep and automatically reconstruct the session event tap.

---

## [0.1.0] - 2026-09-20

### ✨ Added

- **🖱 Native Smooth Scrolling Engine** — Full CVDisplayLink-based smooth scrolling for discrete mouse wheels (Logitech Unifying/Bolt receivers and direct Bluetooth LE). Transforms choppy line-by-line scroll wheel ticks into fluid, momentum-aware inertia scrolling that is visually indistinguishable from a trackpad.
  - **Trackpad Phase Simulation** — Emits correctly sequenced `scrollWheelEventScrollPhase` / `scrollWheelEventMomentumPhase` values so every app that respects macOS scroll momentum (Safari, Maps, PDFs, Xcode canvas) gets natural kinetic deceleration.
  - **Configurable feel** — Speed multiplier, duration/inertia slider, dead-zone threshold, and step normalization, all tunable from the new Smooth Scrolling Preferences tab.
  - **Modifier shortcuts**: hold `Option` for 5× dash scroll, `Shift` to redirect vertical wheel to horizontal axis, `Command` to bypass smoothing entirely — all evaluated from event flags with zero background taps.
  - **Per-application opt-out** — Smooth scrolling can be disabled per app bundle ID from the App Profiles tab (e.g. remote desktop clients bypass smoothing automatically).
  - **Remote desktop auto-bypass** — Automatic pass-through for TeamViewer, AnyDesk, Parsec, RustDesk, Microsoft Remote Desktop, VNC Viewer, TigerVNC, and NeeDisplay.
  - **Discrete wheel detection** — Zero-allocation fast path rejects trackpad, Magic Mouse, continuous momentum, and gesture liftoff events without entering the smooth path.
  - **Reverse scroll** — Independent vertical/horizontal inversion, correctly honoured when shift-redirecting vertical to horizontal.

- **🎛 Smooth Scrolling Preferences Tab** — Full SwiftUI panel for all smooth scrolling parameters with live preview sliders and per-axis toggles.

- **📱 App Profiles Preferences Tab** — New dedicated tab to manage per-application profiles including smooth scroll override per app.

- **🔀 Menu Bar Smooth Scrolling Toggle** — Enable/disable smooth scrolling directly from the menu bar without opening Preferences.

### 🐛 Fixed

- **🔋 Battery telemetry loss on display sleep & screen lock** — Fixed an issue where waking the Mac after the screen turned off (display sleep or lock screen, without system ACPI sleep) caused battery information to disappear. Differentiated display power state from system sleep, implemented a zero-teardown fast path (`handleDisplayWake`) that keeps live IOHID handles intact when the Mac never slept, debounced rapid wake/unlock events, and preserved battery telemetry across transient reconnects.
- **🔋 Battery info missing after system wake** — Mouse battery percentage now remains visible immediately on wake (preserved from the last reading before sleep) and refreshes with a fresh HID++ reading as soon as the Bluetooth link is re-established. A one-shot safety retry at +5 s after wake catches edge cases where the BLE stack silently drops the initial battery request during link re-establishment.

### ⚡ Performance

- **ScrollFilter output lag eliminated** — The smoothing filter previously returned the prior frame's value (`y0`) instead of the current frame (`y1`), adding one full display-refresh of unnecessary output lag (~8 ms at 120 Hz, ~16 ms at 60 Hz). Now returns the current frame.
- **Lock-free scroll frame posting** — `ScrollDispatchContext.postDirectly` previously acquired a second `os_unfair_lock` per CVDisplayLink frame to validate generation and TTL. TTL is now validated inside `preparePostingSnapshot` while the lock is already held, eliminating the redundant acquisition entirely.
- **Single time query per display frame** — `ScrollPoster.processing()` previously called `CFAbsoluteTimeGetCurrent()` twice per frame. Reduced to a single call.
- **Zero-copy scroll config on hot path** — `ScrollManager` now caches `SmoothScrollConfig` as a private value type, updated only on config-change notifications. Eliminates the full `AppConfig` struct copy (~400 B) on every raw scroll event (up to 1 000/s on high-polling mice).
- **Dead code removal** — Eliminated a redundant `enabled` guard in `ScrollManager.handleScrollEvent` (the flag was already gated by an earlier guard-exit). Removed `Interpolator.smoothStep2` and `smoothStep3` (unused, never called, incorrect normalization for mid-animation use).

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

