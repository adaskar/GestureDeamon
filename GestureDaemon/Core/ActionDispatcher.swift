import Cocoa

public final class ActionDispatcher {
    public static let shared = ActionDispatcher()

    private typealias CGSGetSymbolicHotKeyValueFn = @convention(c) (UInt32, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias CGSIsSymbolicHotKeyEnabledFn = @convention(c) (UInt32) -> Bool
    private typealias CGSSetSymbolicHotKeyEnabledFn = @convention(c) (UInt32, Bool) -> Int32
    private typealias CoreDockSendNotificationFn = @convention(c) (CFString, Int32) -> Int32

    private let appServicesHandle: UnsafeMutableRawPointer?

    public init() {
        appServicesHandle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    }

    public func dispatch(action: ActionDefinition?) {
        guard let action = action else { return }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.execute(action: action)
        }
    }

    public func dispatchNavigationBack() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if frontApp.hasPrefix("com.microsoft.VSCode") || frontApp == "com.visualstudio.code.oss" || frontApp == "com.vscodium" {
                // VS Code Go Back: Ctrl + -
                self?.sendSyntheticShortcut(keyCode: 27, modifiers: ["Control"])
            } else {
                // Universal macOS Navigation Back: Cmd + [
                self?.sendSyntheticShortcut(keyCode: 33, modifiers: ["Command"])
            }
        }
    }

    public func dispatchNavigationForward() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if frontApp.hasPrefix("com.microsoft.VSCode") || frontApp == "com.visualstudio.code.oss" || frontApp == "com.vscodium" {
                // VS Code Go Forward: Ctrl + Shift + -
                self?.sendSyntheticShortcut(keyCode: 27, modifiers: ["Control", "Shift"])
            } else {
                // Universal macOS Navigation Forward: Cmd + ]
                self?.sendSyntheticShortcut(keyCode: 30, modifiers: ["Command"])
            }
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
        }
    }

    /// Post native Dock notification via private ApplicationServices SPI (com.apple.expose.awake etc.)
    private func sendDockNotification(_ name: String) -> Bool {
        guard let handle = appServicesHandle,
              let sym = dlsym(handle, "CoreDockSendNotification") else {
            return false
        }
        let fn = unsafeBitCast(sym, to: CoreDockSendNotificationFn.self)
        let res = fn(name as CFString, 0)
        return res == 0
    }

    /// Switch macOS Spaces using WindowServer symbolic hotkey SPI (79: Left, 81: Right).
    /// Retrieves user's exact keycode and modifier flags (including Fn/NX_SECONDARYFNMASK)
    /// and dispatches directly into the login session event tap.
    private func postSymbolicHotKey(_ hotkeyId: UInt32) -> Bool {
        guard let handle = appServicesHandle,
              let symGet = dlsym(handle, "CGSGetSymbolicHotKeyValue"),
              let symIs = dlsym(handle, "CGSIsSymbolicHotKeyEnabled"),
              let symSet = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") else {
            return false
        }

        let getVal = unsafeBitCast(symGet, to: CGSGetSymbolicHotKeyValueFn.self)
        let isEn = unsafeBitCast(symIs, to: CGSIsSymbolicHotKeyEnabledFn.self)
        let setEn = unsafeBitCast(symSet, to: CGSSetSymbolicHotKeyEnabledFn.self)

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
        let loc = CGEventTapLocation.cghidEventTap
        let source = CGEventSource(stateID: .hidSystemState)

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

        usleep(15_000)

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            if keyCode == 27 {
                var char: UniChar = modifiers.map { $0.lowercased() }.contains("shift") ? 0x5F : 0x2D
                keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            }
            keyDown.post(tap: loc)
        }

        usleep(30_000)

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            if keyCode == 27 {
                var char: UniChar = modifiers.map { $0.lowercased() }.contains("shift") ? 0x5F : 0x2D
                keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            }
            keyUp.post(tap: loc)
        }

        usleep(15_000)

        for modKey in modKeyCodes.reversed() {
            if let flagEv = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: false) {
                flagEv.type = .flagsChanged
                flagEv.flags = []
                flagEv.post(tap: loc)
            }
        }
    }
}
