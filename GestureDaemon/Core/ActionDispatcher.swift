import Cocoa

public final class ActionDispatcher {
    public static let shared = ActionDispatcher()

    private typealias CGSGetSymbolicHotKeyValueFn = @convention(c) (UInt32, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias CGSIsSymbolicHotKeyEnabledFn = @convention(c) (UInt32) -> Bool
    private typealias CGSSetSymbolicHotKeyEnabledFn = @convention(c) (UInt32, Bool) -> Int32
    private typealias CoreDockSendNotificationFn = @convention(c) (CFString, Int32) -> Int32

    private let appServicesHandle: UnsafeMutableRawPointer?
    private let coreDockSendNotification: CoreDockSendNotificationFn?
    private let cgsGetSymbolicHotKeyValue: CGSGetSymbolicHotKeyValueFn?
    private let cgsIsSymbolicHotKeyEnabled: CGSIsSymbolicHotKeyEnabledFn?
    private let cgsSetSymbolicHotKeyEnabled: CGSSetSymbolicHotKeyEnabledFn?

    public init() {
        let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        self.appServicesHandle = handle

        if let handle = handle {
            if let sym = dlsym(handle, "CoreDockSendNotification") {
                self.coreDockSendNotification = unsafeBitCast(sym, to: CoreDockSendNotificationFn.self)
            } else {
                self.coreDockSendNotification = nil
            }
            if let sym = dlsym(handle, "CGSGetSymbolicHotKeyValue") {
                self.cgsGetSymbolicHotKeyValue = unsafeBitCast(sym, to: CGSGetSymbolicHotKeyValueFn.self)
            } else {
                self.cgsGetSymbolicHotKeyValue = nil
            }
            if let sym = dlsym(handle, "CGSIsSymbolicHotKeyEnabled") {
                self.cgsIsSymbolicHotKeyEnabled = unsafeBitCast(sym, to: CGSIsSymbolicHotKeyEnabledFn.self)
            } else {
                self.cgsIsSymbolicHotKeyEnabled = nil
            }
            if let sym = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") {
                self.cgsSetSymbolicHotKeyEnabled = unsafeBitCast(sym, to: CGSSetSymbolicHotKeyEnabledFn.self)
            } else {
                self.cgsSetSymbolicHotKeyEnabled = nil
            }
        } else {
            self.coreDockSendNotification = nil
            self.cgsGetSymbolicHotKeyValue = nil
            self.cgsIsSymbolicHotKeyEnabled = nil
            self.cgsSetSymbolicHotKeyEnabled = nil
        }
    }

    public func dispatch(action: ActionDefinition?) {
        guard let action = action else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.execute(action: action)
        }
    }

    public func dispatchNavigationBack() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            // Universal macOS Navigation Back: Cmd + [
            self?.sendSyntheticShortcut(keyCode: 33, modifiers: ["Command"])
        }
    }

    public func dispatchNavigationForward() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            // Universal macOS Navigation Forward: Cmd + ]
            self?.sendSyntheticShortcut(keyCode: 30, modifiers: ["Command"])
        }
    }

    private func execute(action: ActionDefinition) {
        switch action.type {
        case .shortcut:
            guard let keyCode = action.keyCode else { return }
            let mods = action.modifiers ?? []
            let isCtrlOnly = mods.count == 1 && ["control", "ctrl"].contains(mods[0].lowercased())

            // Native Dock / WindowServer handlers (same mechanism used by OpenLogi)
            if isCtrlOnly {
                switch keyCode {
                case 126: // Ctrl + Up -> Mission Control
                    if sendDockNotification("com.apple.expose.awake") { return }
                case 125: // Ctrl + Down -> App Exposé
                    if sendDockNotification("com.apple.expose.front.awake") { return }
                case 123: // Ctrl + Left -> Move left a space (Symbolic HotKey 79)
                    if postSymbolicHotKey(79) { return }
                case 124: // Ctrl + Right -> Move right a space (Symbolic HotKey 81)
                    if postSymbolicHotKey(81) { return }
                default:
                    break
                }
            }

            // Fallback for custom configured shortcuts
            sendSyntheticShortcut(keyCode: CGKeyCode(keyCode), modifiers: mods)

        case .application:
            guard let bundleId = action.bundleIdentifier,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)

        case .command:
            guard let command = action.commandPath else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            try? process.run()

        case .system:
            guard let sysAct = action.systemAction else { return }
            switch sysAct.lowercased() {
            case "volumeup":
                sendMediaKey(0) // NX_KEYTYPE_SOUND_UP
            case "volumedown":
                sendMediaKey(1) // NX_KEYTYPE_SOUND_DOWN
            case "mute":
                sendMediaKey(7) // NX_KEYTYPE_MUTE
            case "brightnessup":
                sendMediaKey(2) // NX_KEYTYPE_BRIGHTNESS_UP
            case "brightnessdown":
                sendMediaKey(3) // NX_KEYTYPE_BRIGHTNESS_DOWN
            default:
                break
            }
        }
    }

    /// Post native macOS system media key event (Volume, Brightness, Mute) to cghidEventTap
    private func sendMediaKey(_ key: Int32) {
        func postKey(down: Bool) {
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            if let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: down ? NSEvent.ModifierFlags(rawValue: 0xa00) : [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) {
                let cgEv = ev.cgEvent
                cgEv?.post(tap: .cghidEventTap)
            }
        }
        postKey(down: true)
        postKey(down: false)
    }

    /// Post native Dock notification via pre-resolved ApplicationServices SPI (com.apple.expose.awake etc.)
    private func sendDockNotification(_ name: String) -> Bool {
        guard let fn = coreDockSendNotification else { return false }
        return fn(name as CFString, 0) == 0
    }

    /// Switch macOS Spaces using WindowServer symbolic hotkey SPI (79: Left, 81: Right).
    /// Retrieves user's exact keycode and modifier flags (including Fn/NX_SECONDARYFNMASK)
    /// and dispatches directly into the login session event tap.
    private func postSymbolicHotKey(_ hotkeyId: UInt32) -> Bool {
        guard let getVal = cgsGetSymbolicHotKeyValue,
              let isEn = cgsIsSymbolicHotKeyEnabled,
              let setEn = cgsSetSymbolicHotKeyEnabled else {
            return false
        }

        var keyEq: UInt16 = 0
        var vKey: UInt16 = 0
        var mods: UInt32 = 0
        let res = getVal(hotkeyId, &keyEq, &vKey, &mods)
        guard res == 0 else { return false }

        // Ensure symbolic hotkey is enabled
        if !isEn(hotkeyId) {
            _ = setEn(hotkeyId, true)
        }

        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(vKey), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(vKey), keyDown: false) else {
            return false
        }

        let flags = CGEventFlags(rawValue: UInt64(mods))
        down.flags = flags
        up.flags = flags

        // Post to .cgSessionEventTap so WindowServer / Dock intercepts it as a session hotkey
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    private func sendSyntheticShortcut(keyCode: CGKeyCode, modifiers: [String]) {
        Log.info("⚡ [SYNTHETIC SHORTCUT] Injecting keyCode=\(keyCode), modifiers=\(modifiers) into cgSessionEventTap")

        let loc = CGEventTapLocation.cgSessionEventTap
        let source = CGEventSource(stateID: .combinedSessionState)

        var modKeyCodes: [CGKeyCode] = []
        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "control", "ctrl":
                modKeyCodes.append(59)
                flags.insert([.maskControl, CGEventFlags(rawValue: 0x01)])
            case "option", "alt":
                modKeyCodes.append(58)
                flags.insert([.maskAlternate, CGEventFlags(rawValue: 0x20)])
            case "shift":
                modKeyCodes.append(56)
                flags.insert([.maskShift, CGEventFlags(rawValue: 0x02)])
            case "command", "cmd":
                modKeyCodes.append(55)
                flags.insert([.maskCommand, CGEventFlags(rawValue: 0x08)])
            default: break
            }
        }

        for modKey in modKeyCodes {
            if let flagEv = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: true) {
                flagEv.type = .flagsChanged
                flagEv.flags = flags
                flagEv.post(tap: loc)
            }
        }

        if !modKeyCodes.isEmpty {
            usleep(1_500)
        }

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: loc)
        }

        usleep(3_000)

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: loc)
        }

        if !modKeyCodes.isEmpty {
            usleep(1_500)
            for modKey in modKeyCodes.reversed() {
                if let flagEv = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: false) {
                    flagEv.type = .flagsChanged
                    flagEv.flags = []
                    flagEv.post(tap: loc)
                }
            }
        }
    }
}
