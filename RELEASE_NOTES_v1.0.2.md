# GestureDaemon v1.0.2 — Post-Sleep Click Fix & Zero Keyboard Overhead ⌨️🌙

> **Ultra-lightweight, zero-telemetry native macOS background daemon and menu bar utility replacing Logitech Options+ for multi-button mice.**

**GestureDaemon v1.0.2** is a stability and performance release fixing a leftover sleep-wake edge case and eliminating CPU overhead caused by system-wide keyboard event interception.

---

## 🌟 What's New in v1.0.2

### 🐛 Fixed

#### 🌙 Thumb Button Single-Click Not Working After Sleep
After sleep (especially display sleep), the thumb button single-click could stop responding until the user manually toggled **Pause → Resume Gestures** from the menu bar.

**Root cause**: macOS can fully *invalidate* a CGEventTap's underlying `CFMachPort` during sleep transitions — not just disable it. The previous fix in v1.0.1 called `CGEvent.tapEnable` on the dead port, which is a silent no-op. The tap appeared alive (the `CFMachPort` pointer was non-nil) but was doing nothing.

**Fix**: `ensureTapActive()` now checks `CFMachPortIsValid(tap)` first. If the port is dead it performs a full `stop()` + `start()` rebuild before returning. The same check is applied inside `handlePrimaryEvent` when macOS sends `tapDisabledByUserInput` (the sleep signal), routing through `ensureTapActive()` instead of the bare `tapEnable` call.

---

### ⚡ Performance

#### ⌨️ Zero Keyboard IPC Overhead While Typing
CPU usage was noticeably elevated whenever the keyboard was used — even when typing in a completely unrelated app (TextEdit, terminal, browser, etc.).

**Root cause**: The primary always-on `CGEventTap` was subscribed to `keyDown`, `keyUp`, and `flagsChanged` system-wide at `headInsertEventTap` level. Every keystroke had to be routed through GestureDaemon via Mach IPC (context-switch out, callback, context-switch back) even though 99% of keystrokes were immediately passed through unchanged.

**Fix**: Keyboard events have been moved to a new **dynamic keyboard tap** that follows the same lifecycle pattern as the existing dynamic motion tap. The keyboard tap is only active when genuinely needed:

| State | Keyboard Tap |
|---|---|
| HID++ device connected (normal operation) | **OFF** — zero keyboard IPC overhead |
| Logitech device detected, HID++ discovery in progress | **ON** (brief transient window) |
| No Logitech device connected at all | **OFF** — no mouse = no macro possible |
| Shortcut recording session open in Preferences | **ON** |
| Logitech macro mid-flight (modifier cleanup) | **ON** |

When your Logitech mouse is connected via HID++ (USB receiver or direct Bluetooth), the firmware sends gesture events as HID++ reports directly and never sends the Cmd+Opt+Tab software macro — so the keyboard tap has nothing to do and stays completely off. When the mouse is **disconnected entirely**, there is no mouse firmware to send any macro either, so the tap stays off then too.

#### 🔔 Fixed: Keyboard Tap Not Turning Off After Device Connected
The `hidHardwareCapabilitiesDidChange` observer that was supposed to stop the keyboard tap when the HID++ device connected was registered using `addObserver(_:selector:)` targeting a non-`NSObject` Swift class. `NSNotificationCenter` cannot guarantee `performSelector:` dispatch on non-`NSObject` targets at runtime, so the callback was silently never firing — meaning `updateKeyboardTapState()` was never called after device connection, and the keyboard tap stayed alive indefinitely.

**Fix**: Switched to the block-based `addObserver(forName:object:queue:using:)` form, which works correctly with any Swift type regardless of `NSObject` inheritance.

#### 🔌 Fixed: Keyboard Tap Activating When Mouse Is Disconnected
When the Logitech mouse was unplugged, `isDeviceOpen` became `false` and the keyboard tap turned back on (it was originally designed to cover the macro fallback path). But with no Logitech device physically present, the mouse firmware cannot send Cmd+Opt+Tab regardless — so intercepting every keystroke was pointless CPU waste.

**Fix**: Added `HIDPlusPlusManager.hasManagedDevice` (true while at least one `IOHIDDevice` is tracked, false when none are). The macro-fallback condition is now `hasManagedDevice && !isDeviceOpen` — the keyboard tap only activates in the narrow window where a Logitech device is physically present but HID++ feature discovery hasn't completed yet. Mouse fully disconnected = `hasManagedDevice` false = tap off = zero CPU while typing.

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

**Full Changelog**: https://github.com/adaskar/GestureDeamon/compare/v1.0.1...v1.0.2
