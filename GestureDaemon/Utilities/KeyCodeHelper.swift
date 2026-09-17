import Cocoa
import Carbon

public enum KeyCodeHelper {

    // MARK: - Well-Known Special Key Names & Symbols
    private static let specialKeySymbols: [UInt16: (symbol: String, name: String)] = [
        126: ("↑", "Up Arrow"),
        125: ("↓", "Down Arrow"),
        123: ("←", "Left Arrow"),
        124: ("→", "Right Arrow"),
        36:  ("↩", "Return"),
        48:  ("⇥", "Tab"),
        49:  ("␣", "Space"),
        51:  ("⌫", "Delete"),
        117: ("⌦", "Forward Delete"),
        53:  ("⎋", "Escape"),
        71:  ("⌧", "Clear"),
        76:  ("⌤", "Enter"),
        115: ("↖", "Home"),
        119: ("↘", "End"),
        116: ("⇞", "Page Up"),
        121: ("⇟", "Page Down"),
        122: ("F1", "F1"),
        120: ("F2", "F2"),
        99:  ("F3", "F3"),
        118: ("F4", "F4"),
        96:  ("F5", "F5"),
        97:  ("F6", "F6"),
        98:  ("F7", "F7"),
        100: ("F8", "F8"),
        101: ("F9", "F9"),
        109: ("F10", "F10"),
        103: ("F11", "F11"),
        111: ("F12", "F12"),
        105: ("F13", "F13"),
        107: ("F14", "F14"),
        113: ("F15", "F15"),
        106: ("F16", "F16"),
        64:  ("F17", "F17"),
        79:  ("F18", "F18"),
        80:  ("F19", "F19"),
        90:  ("F20", "F20")
    ]

    // Fallback dictionary for standard US ANSI keycodes when dynamic translation is unavailable
    private static let fallbackKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`"
    ]

    // MARK: - KeyCode to Display String

    /// Converts a virtual key code to a layout-accurate character or key name
    public static func keyString(for keyCode: UInt16) -> String {
        // 1. Check special keys first
        if let special = specialKeySymbols[keyCode] {
            return special.symbol
        }

        // 2. Query active keyboard layout via Carbon UCKeyTranslate
        if let character = characterFromCarbon(keyCode: keyCode) {
            return character.uppercased()
        }

        // 3. Fallback to known static map
        if let name = fallbackKeyNames[keyCode] {
            return name
        }

        return "Key \(keyCode)"
    }

    /// Descriptive name of the key (e.g. "Up Arrow" instead of "↑")
    public static func keyDescriptiveName(for keyCode: UInt16) -> String {
        if let special = specialKeySymbols[keyCode] {
            return special.name
        }
        return keyString(for: keyCode)
    }

    /// Dynamic layout resolver using macOS Carbon InputSource API
    public static func characterFromCarbon(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        guard let rawPtr = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        let keyboardLayout = rawPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
        var deadKeyState: UInt32 = 0
        var actualStringLength: Int = 0
        var unicodeChars = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0, // modifiers
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &actualStringLength,
            &unicodeChars
        )

        guard status == noErr, actualStringLength > 0 else {
            return nil
        }

        let str = String(utf16CodeUnits: unicodeChars, count: actualStringLength)
        // Filter out non-printable control characters
        let trimmed = str.trimmingCharacters(in: .controlCharacters)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Dynamically finds the virtual key code and required shift modifier for a given character on the current keyboard layout
    public static func findKey(for targetChar: Character) -> (keyCode: UInt16, requiresShift: Bool)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        guard let rawPtr = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = rawPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)

        // 1. Try unshifted keycodes (0..<128)
        for k: UInt16 in 0..<128 {
            var actualLen: Int = 0
            deadKeyState = 0
            let status = UCKeyTranslate(
                keyboardLayout, k, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, 4, &actualLen, &chars
            )
            if status == noErr, actualLen > 0 {
                let str = String(utf16CodeUnits: chars, count: actualLen)
                if str == String(targetChar) {
                    return (k, false)
                }
            }
        }

        // 2. Try shifted keycodes (0..<128)
        for k: UInt16 in 0..<128 {
            var actualLen: Int = 0
            deadKeyState = 0
            let status = UCKeyTranslate(
                keyboardLayout, k, UInt16(kUCKeyActionDisplay), UInt32(shiftKey >> 8),
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, 4, &actualLen, &chars
            )
            if status == noErr, actualLen > 0 {
                let str = String(utf16CodeUnits: chars, count: actualLen)
                if str == String(targetChar) {
                    return (k, true)
                }
            }
        }

        return nil
    }

    // MARK: - Modifiers Formatting

    public static let standardModifierOrder = ["Control", "Option", "Shift", "Command"]

    public static func modifierSymbol(for modifier: String) -> String {
        switch modifier.lowercased() {
        case "control", "ctrl":
            return "⌃"
        case "option", "alt", "opt":
            return "⌥"
        case "shift":
            return "⇧"
        case "command", "cmd":
            return "⌘"
        default:
            return modifier
        }
    }

    public static func sortedModifiers(_ modifiers: [String]) -> [String] {
        return modifiers.sorted { a, b in
            let idxA = standardModifierOrder.firstIndex(where: { $0.caseInsensitiveCompare(a) == .orderedSame }) ?? 999
            let idxB = standardModifierOrder.firstIndex(where: { $0.caseInsensitiveCompare(b) == .orderedSame }) ?? 999
            return idxA < idxB
        }
    }

    public static func formattedModifiersString(_ modifiers: [String]?) -> String {
        guard let modifiers = modifiers, !modifiers.isEmpty else { return "" }
        let sorted = sortedModifiers(modifiers)
        return sorted.map { modifierSymbol(for: $0) }.joined()
    }

    public static func formattedShortcut(keyCode: UInt16?, modifiers: [String]?) -> String {
        guard let keyCode = keyCode else { return "None" }
        let modStr = formattedModifiersString(modifiers)
        let key = keyString(for: keyCode)
        if modStr.isEmpty {
            return key
        }
        return "\(modStr) \(key)"
    }

    // MARK: - NSEvent Modifiers Conversion

    public static func modifiersFromNSEventFlags(_ flags: NSEvent.ModifierFlags) -> [String] {
        var mods: [String] = []
        if flags.contains(.control) { mods.append("Control") }
        if flags.contains(.option) { mods.append("Option") }
        if flags.contains(.shift) { mods.append("Shift") }
        if flags.contains(.command) { mods.append("Command") }
        return mods
    }

    public static func nsEventFlagsFromModifiers(_ modifiers: [String]?) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        guard let modifiers = modifiers else { return flags }
        for mod in modifiers {
            switch mod.lowercased() {
            case "control", "ctrl":
                flags.insert(.control)
            case "option", "alt", "opt":
                flags.insert(.option)
            case "shift":
                flags.insert(.shift)
            case "command", "cmd":
                flags.insert(.command)
            default: break
            }
        }
        return flags
    }

    // MARK: - Standard Presets Library

    public struct PresetAction: Identifiable, Hashable {
        public var id: String { name }
        public let name: String
        public let description: String
        public let action: ActionDefinition

        public static let presets: [PresetAction] = [
            PresetAction(
                name: "Mission Control",
                description: "Shows all open windows across all spaces (⌃↑)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 126,
                    modifiers: ["Control"],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Mission Control (Ctrl+Up)"
                )
            ),
            PresetAction(
                name: "App Exposé",
                description: "Shows all windows of the frontmost application (⌃↓)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 125,
                    modifiers: ["Control"],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "App Exposé (Ctrl+Down)"
                )
            ),
            PresetAction(
                name: "Move Left a Space",
                description: "Switches to the previous virtual desktop / Space (⌃←)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 123,
                    modifiers: ["Control"],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Move Left a Space (Ctrl+Left)"
                )
            ),
            PresetAction(
                name: "Move Right a Space",
                description: "Switches to the next virtual desktop / Space (⌃→)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 124,
                    modifiers: ["Control"],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Move Right a Space (Ctrl+Right)"
                )
            ),
            PresetAction(
                name: "Show Desktop",
                description: "Hides all application windows to reveal Desktop (F11)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 103,
                    modifiers: [],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Show Desktop (F11)"
                )
            ),
            PresetAction(
                name: "Navigation Back",
                description: "Navigates back in Web Browsers, Finder, and IDEs (⌘[)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 33,
                    modifiers: ["Command"],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Navigation Back (Cmd+[)"
                )
            ),
            PresetAction(
                name: "Volume Up",
                description: "Increases system audio volume with native macOS HUD",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "volumeUp",
                    comment: "Volume Up"
                )
            ),
            PresetAction(
                name: "Volume Down",
                description: "Decreases system audio volume with native macOS HUD",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "volumeDown",
                    comment: "Volume Down"
                )
            ),
            PresetAction(
                name: "Mute / Unmute",
                description: "Toggles system audio mute",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "mute",
                    comment: "Mute / Unmute"
                )
            ),
            PresetAction(
                name: "Brightness Up",
                description: "Increases display brightness with native macOS HUD",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "brightnessUp",
                    comment: "Brightness Up"
                )
            ),
            PresetAction(
                name: "Brightness Down",
                description: "Decreases display brightness with native macOS HUD",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "brightnessDown",
                    comment: "Brightness Down"
                )
            ),
            PresetAction(
                name: "Next Tab",
                description: "Switches to next tab in browsers and IDEs (⌘⇧])",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 30,
                    modifiers: ["Command", "Shift"],
                    comment: "Next Tab (Cmd+Shift+])"
                )
            ),
            PresetAction(
                name: "Previous Tab",
                description: "Switches to previous tab in browsers and IDEs (⌘⇧[)",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 33,
                    modifiers: ["Command", "Shift"],
                    comment: "Previous Tab (Cmd+Shift+[)"
                )
            ),
            PresetAction(
                name: "Zoom In",
                description: "Zooms in current document or page (⌘+)",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "zoomIn",
                    comment: "Zoom In"
                )
            ),
            PresetAction(
                name: "Zoom Out",
                description: "Zooms out current document or page (⌘-)",
                action: ActionDefinition(
                    type: .system,
                    systemAction: "zoomOut",
                    comment: "Zoom Out"
                )
            ),
            PresetAction(
                name: "Navigation Forward",
                description: "Navigates forward in Web Browsers, Finder, and IDEs (⌘])",
                action: ActionDefinition(
                    type: .shortcut,
                    keyCode: 30,
                    modifiers: ["Command"],
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Navigation Forward (Cmd+])"
                )
            )
        ]
    }
}

