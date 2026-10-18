# GestureDaemon v1.0.3 — Deep Sleep Wake Gesture Recovery 🌙⚡

> **Ultra-lightweight, zero-telemetry native macOS background daemon and menu bar utility replacing Logitech Options+ for multi-button mice.**

**GestureDaemon v1.0.3** resolves a critical hardware synchronization edge case where mouse gestures and thumb-button single clicks stopped responding after the Mac woke from deep ACPI sleep.

---

## 🌟 What's New in v1.0.3

### 🐛 Fixed

#### 🌙 Deep Sleep Wake Gesture & Thumb-Button Recovery
When waking the Mac from deep sleep (such as opening the MacBook lid), mouse gestures and thumb-button single-clicks (e.g. Mission Control) could become unresponsive until the user manually toggled **Pause → Resume Gestures** from the menu bar, even though Side Buttons (Back / Forward) continued working normally.

**Root cause**:
1. **Wake Event Suppression**: macOS posts `screensDidWakeNotification` (display wake) 5–20 ms before `didWakeNotification` (system wake). Because both notifications previously shared cross-checking deduplication timers, the display wake ran first and recorded its timestamp, causing `handleSystemWake()` to be suppressed as a duplicate. Consequently, `HIDPlusPlusManager.shared.handleWake()` was never called.
2. **Stale Device Handles**: The fallback `handleDisplayWake()` did not invalidate pre-sleep device handles, so it skipped device matching and attempted to write HID++ control reports to dead IOKit handles.
3. **Suppressed Fallback Macro**: Because device handles were not marked closed, the keyboard fallback tap (`Cmd+Opt+Tab` hardware macro emitted by Logitech mice when undiverted) was kept inactive, causing both the HID++ diversion pipeline and the keyboard macro fallback pipeline to fail simultaneously.

**Fix**:
- **Stateful Wake Promotion (`SleepWakeManager`)**: Added an `isSystemSleeping` latch. Whichever wake event arrives first upon waking promotes cleanly to a full system wake and triggers `HIDPlusPlusManager.shared.handleWake()`. Cross-event timestamp suppression has been eliminated.
- **Diversion Tracking & Invalidation (`HIDPlusPlusManager`)**: Introduced `isHardwareDiverted`. Stale device handles are marked closed on sleep, and failed report sets automatically re-trigger matching to obtain fresh IOKit device references.
- **Continuous Macro Fallback (`EventTapManager`)**: The fallback keyboard tap now activates whenever `!hid.isHardwareDiverted`, guaranteeing that clicks registered via the mouse's internal hardware macro work seamlessly while Bluetooth links renegotiate.
- **Pass-through on Disengaged Up Event (`GestureStateMachine`)**: `handleMagicUp()` now returns `false` (pass-through) if an unengaged button-up event arrives, ensuring actions are never swallowed.

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

