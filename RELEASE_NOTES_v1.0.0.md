# GestureDaemon v1.0.0 — General Availability 🚀

> **Ultra-lightweight, zero-telemetry native macOS background daemon and menu bar utility replacing Logitech Options+ for multi-button mice.**

We are thrilled to announce **GestureDaemon 1.0.0**, our first official production release! This milestone delivers rock-solid hardware stability, complete feature parity with proprietary suites (Logitech Options+ / Logi G HUB), trackpad-smooth scrolling, and refined battery telemetry—all in a standalone native binary that uses **0.0% idle CPU** and under 15 MB of RAM.

---

## 🌟 Highlights in v1.0.0

### 🔋 Qualitative & Stepped Battery Telemetry Engine
* **Fixed HID++ 2.0 Unified Battery (`0x1004`) Parsing**: Corrected payload decoding for hardware coarse level (byte 5) and charging status (byte 6).
* **Qualitative Health Normalization**: Resolved the common confusion where Logitech Options showed *"Battery level is good"* while third-party apps showed an arbitrary `50%`. Devices with stepped voltage comparators (such as the M720 Triathlon with AA battery, MX Master 2S/3/3S, etc.) now display clean qualitative health (`Good`, `Full`, `Low`, `Critical`).
* **Zero Discrepancy with macOS Bluetooth**: Harmonized presentation so that Logitech hardware status no longer contradicts macOS Bluetooth menu's uncalibrated GATT reading.
* **Unified `displayText` Architecture**: Automatically displays qualitative states (`Good`) for stepped hardware and granular percentages (`85%`) for devices with hardware fuel-gauge ICs.

### 🖱️ Trackpad-Quality Smooth Scrolling
* **CVDisplayLink 120 Hz / 60 Hz Inertia Engine**: Transforms notched, discrete mouse wheel clicks into fluid kinetic scrolling visually indistinguishable from an Apple Magic Trackpad.
* **Trackpad Phase Simulation**: Accurately emits `scrollWheelEventScrollPhase` and `scrollWheelEventMomentumPhase` so Safari, Xcode, Maps, and Preview decelerate with natural physics.
* **Smart Modifier Shortcuts**: Hold `Option` for 5× dash-scroll, `Shift` to redirect vertical wheel ticks to the horizontal axis, and `Command` to bypass smoothing entirely.
* **Per-App Remote Desktop Pass-Through**: Automatic smoothing bypass for TeamViewer, AnyDesk, Parsec, RustDesk, Microsoft Remote Desktop, and VNC clients.

### 🎛️ Full Native SwiftUI Preferences Suite (`⌘,`)
* **6 Dedicated Configuration Tabs**:
  * **Gestures**: Thumb flick triggers (Up, Down, Left, Right) & single press actions.
  * **Side Buttons**: Buttons 3 & 4 history navigation with custom key combinations.
  * **App Profiles**: Custom per-application gesture and scrolling overrides.
  * **Smooth Scrolling**: Inertia duration, speed multiplier, deadzone, and axis inversion.
  * **General & Tuning**: Hardware controls (SmartShift, DPI, battery telemetry), drag sensitivity, and startup options.
  * **Live Calibration Canvas**: Interactive real-time displacement vectors, boundary rings, and gesture recognition visualization.
* **International Keyboard Normalization**: Interactive shortcut recorder works seamlessly across QWERTY, AZERTY, Turkish Q, Dvorak, Colemak, and international layouts.

### ⚡ Performance & Dual-Transport Architecture
* **True 0.0% Idle CPU**: Ephemeral event-tap lifecycle guarantees zero background wakeups during mouse movement.
* **Dual-Transport Logitech HID++ 2.0**: Native hardware button diversion (`0x1B04` CID `0x00C3`) over both USB Unifying/Bolt receivers (`0xFF00`) and direct Bluetooth Low Energy (`0xFF43:0x0202`).
* **Sleep / Wake & Display Lock Resilience**: Staged re-diversion and telemetry persistence across ACPI sleep, screen lock, and display sleep transitions.

---

## 📦 Download & Installation

### Option 1: Download Pre-built Release Asset
1. Download **`GestureDaemon.app.zip`** (or **`GestureDaemon.dmg`**) from the Assets below.
2. Unzip and drag `GestureDaemon.app` to `/Applications`.
3. Launch `GestureDaemon.app` and grant Accessibility permissions when prompted.

### Option 2: Build from Source (Gatekeeper-Free)
```bash
git clone https://github.com/adaskar/GestureDeamon.git
cd GestureDeamon
make app-arm64    # or 'make app' for Universal (Apple Silicon + Intel)
open build/GestureDaemon.app
```

---

## 📋 Compatibility
* **macOS**: macOS 13.0 Ventura, macOS 14 Sonoma, macOS 15 Sequoia, and newer.
* **Architecture**: Universal binary (Apple Silicon arm64 + Intel x86_64).
* **Hardware Tested**: Logitech M720 Triathlon, MX Master 3S, MX Master 3, MX Master 2S, MX Anywhere 3, and standard 5-button USB/BLE mice.

---

**Full Changelog**: https://github.com/adaskar/GestureDeamon/compare/v0.1.0...v1.0.0
