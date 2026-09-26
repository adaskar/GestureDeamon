# GestureDaemon v1.0.1 — Sleep / Wake Recovery & Hardware Fix 🌙🛠️

> **Ultra-lightweight, zero-telemetry native macOS background daemon and menu bar utility replacing Logitech Options+ for multi-button mice.**

**GestureDaemon v1.0.1** is a critical stability release resolving a hardware diversion drop after display sleep, screen lock, and ACPI system sleep on Bluetooth Low Energy devices (such as the Logitech M720 Triathlon and MX Master series).

---

## 🌟 What's New & Fixed in v1.0.1

### 🌙 Rock-Solid Staged Sleep / Wake Recovery Engine
* **Fixed Gestures Ceasing After Sleep**: Resolved an issue where mouse gestures stopped working after macOS or display sleep until the user manually toggled "Pause Gestures" and "Resume Gestures" in the status menu.
* **Direct Bluetooth LE Button Diversion**: Fixed an omission in `reapplyHardwareDiversion()` where direct Bluetooth LE mice skipped calling `divertGestureButtons(...)` when waking with already-cached feature indices.
* **Staged Hardware Recovery Pipeline**: Unified wake handling with staged retry passes at $t=0$, $+1.0\text{s}$, $+2.5\text{s}$, and $+4.0\text{s}$. This guarantees that when Logitech mouse hardware renegotiates its BLE L2CAP connection following low-power sleep, its hardware registers are immediately restored to gesture diversion mode.
* **Mach Port Auto-Reconstruction**: Enhanced `EventTapManager.ensureTapActive()` to verify `CFMachPortIsValid(...)`. If macOS WindowServer invalidates the underlying Mach port during sleep transitions, the event tap is automatically torn down and reconstructed without dropping user input.

---

## 📦 Download & Installation

### Option 1: Download Pre-built Release Asset
1. Download **`GestureDaemon.zip`** from the Assets below.
2. Unzip and drag `GestureDaemon.app` to your `/Applications` folder.
3. Launch `GestureDaemon.app` (or click *Restart GestureDaemon* from the menu bar if already running).

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
* **Architecture**: Universal binary (Apple Silicon `arm64` + Intel `x86_64`).
* **Hardware Verified**: Logitech M720 Triathlon, MX Master 3S, MX Master 3, MX Master 2S, MX Anywhere 3, and standard 5-button USB/BLE mice.

---

**Full Changelog**: https://github.com/adaskar/GestureDeamon/compare/v1.0.0...v1.0.1
