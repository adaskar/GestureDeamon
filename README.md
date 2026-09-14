# GestureDaemon

> **Ultra-lightweight, zero-telemetry native macOS background daemon and menu bar utility replacing Logitech Options+ for multi-button mice.**

Built in pure Swift with zero third-party dependencies. Consumes **0.0% idle CPU** and less than 15 MB RAM while delivering native, instant Mission Control and Desktop Spaces gesture transitions.

---

## Highlights

- ⚡️ **True 0.0% Idle CPU**: Ephemeral event-tap lifecycle guarantees zero IPC wakeups and zero context switches during normal mouse and trackpad pointer motion.
- 🪟 **Native macOS Desktop Switching**: Ported reverse-engineered CoreGraphics Services (CGS) SPI with `NX_SECONDARYFNMASK` modifier injection for flawless Spaces transitions.
- 🎯 **Mission Control & App Exposé**: Instant Exposé triggers via private `CoreDockSendNotification`.
- 🧼 **Modifier Sanitization**: Unconditionally swallows Logitech's hardware fallback `Cmd+Option+Tab` thumb macro and clears modifier flags—preventing VS Code or browser tab bars from stealing focus.
- 🧭 **Universal Side Button Navigation (Back & Forward)**: Intercepts thumb side buttons (Buttons 3 & 4) and translates them into instant history navigation (`Cmd+[` / `Cmd+]`) across Safari, Chrome, Finder, and smart code navigation (`Ctrl+-` / `Ctrl+Shift+-`) in VS Code.
- 🎛 **Customizable `config.plist` with Live Hot-Reloading**: Edit settings in `~/.config/GestureDaemon/config.plist` and changes apply immediately without restarting.
- 🍏 **Modern macOS Agent**: Native `.app` bundle with `LSUIElement=true`, status bar controller (`NSStatusItem`), "Hide Menu Bar Icon" support with headless reopen recovery, and modern `SMAppService` launch-at-login integration.
- 📦 **Standard DMG Packaging**: Automated `make dmg` drag-and-drop installer.

---

## Quick Installation

### From Pre-Built DMG
1. Download or build `GestureDaemon.dmg`.
2. Open the disk image and drag **GestureDaemon** into `/Applications`.
3. Launch **GestureDaemon** from Applications or Spotlight.
4. When prompted, enable Accessibility in **System Settings → Privacy & Security → Accessibility**.

### From Source
```bash
# Clone the repository
git clone https://github.com/guru/GestureDaemon.git
cd GestureDaemon

# Build universal application bundle and DMG
make all

# Install directly to /Applications
make install
```

---

## Default Controls & Gestures (Logitech M720 / MX Master)

### Gestures (Thumb Button / Rest)
Hold the **Thumb Gesture Button** (or flick your wrist) and release:

| Gesture | Action | Implementation |
|---|---|---|
| **Stationary Click** | Mission Control | `CoreDockSendNotification("com.apple.expose.awake")` |
| **Flick Left** | Switch to Right Desktop | CGS Symbolic HotKey `81` (`Ctrl + Right`) |
| **Flick Right** | Switch to Left Desktop | CGS Symbolic HotKey `79` (`Ctrl + Left`) |
| **Flick Down** | App Exposé | `CoreDockSendNotification("com.apple.expose.front.awake")` |

*Evaluation Window: 200 ms. Threshold: 35 pt. Deadzone: 8 pt.*

### Side Navigation Buttons
| Physical Button | Button Index | Default Action | Supported Contexts |
|---|---|---|---|
| **Back Button** | `3` | Navigate Back | Safari, Chrome, Finder (`Cmd + [`), VS Code (`Ctrl + -`) |
| **Forward Button** | `4` | Navigate Forward | Safari, Chrome, Finder (`Cmd + ]`), VS Code (`Ctrl + Shift + -`) |

*Configurable via `BackButtonAction` and `ForwardButtonAction` in `config.plist`.*

---

## Full Documentation

For deep technical details, parameter dictionaries, keycode reference tables, pre-made configuration recipes (developer, media, web browsing), and our future feature roadmap, see:

📖 **[Full Architecture, Configuration Guide & Roadmap (DOCUMENTATION.md)](DOCUMENTATION.md)**

---

## License

MIT License. Crafted with precision for macOS.

