import Cocoa

public final class ActionDispatcher {
    public static let shared = ActionDispatcher()
    private let eventSource = CGEventSource(stateID: .privateState)

    public func dispatch(action: ActionDefinition?) {
        guard let action = action else { return }
        switch action.type {
        case .shortcut:
            guard let keyCode = action.keyCode else { return }
            sendSyntheticShortcut(keyCode: CGKeyCode(keyCode), flags: parseModifierFlags(action.modifiers ?? []))
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

    private func sendSyntheticShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            Log.error("Failed to construct CGEvents for keycode \(keyCode)")
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        usleep(15_000)
        keyUp.post(tap: .cghidEventTap)
    }

    private func parseModifierFlags(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "control", "ctrl": flags.insert(.maskControl)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "command", "cmd": flags.insert(.maskCommand)
            default: break
            }
        }
        return flags
    }
}

