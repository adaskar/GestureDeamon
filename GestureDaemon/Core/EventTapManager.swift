import Cocoa
import CoreGraphics

public final class EventTapManager {
    public static let shared = EventTapManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let stateMachine = GestureStateMachine()
    private var diagnosticMode = false
    public var isPaused: Bool = false

    private init() {}

    public func enableDiagnostics(_ enabled: Bool) { self.diagnosticMode = enabled }

    public func start() {
        var eventMask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
                                  | (1 << CGEventType.otherMouseUp.rawValue)
                                  | (1 << CGEventType.otherMouseDragged.rawValue)
                                  | (1 << CGEventType.mouseMoved.rawValue)
                                  | (1 << CGEventType.keyDown.rawValue)
                                  | (1 << CGEventType.keyUp.rawValue)
                                  | (1 << CGEventType.flagsChanged.rawValue)

        if diagnosticMode {
            eventMask |= (1 << CGEventType.leftMouseDown.rawValue)
                      | (1 << CGEventType.leftMouseUp.rawValue)
                      | (1 << CGEventType.rightMouseDown.rawValue)
                      | (1 << CGEventType.rightMouseUp.rawValue)
        }

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            Log.error("Failed to create CGEventTap. Check Accessibility permission.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.info("CGEventTap engaged.")
    }

    public func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        self.eventTap = nil
        self.runLoopSource = nil
        Log.info("CGEventTap disconnected.")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.error("EventTap disabled by macOS. Re-enabling...")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

        if diagnosticMode {
            switch type {
            case .otherMouseDown, .otherMouseUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
                print("[DIAGNOSTIC] Mouse Event: type=\(type.rawValue), buttonNumber=\(buttonNumber)")
            case .keyDown, .keyUp:
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                print("[DIAGNOSTIC] Keyboard Event: type=\(type.rawValue), keyCode=\(keycode), flags=0x\(String(event.flags.rawValue, radix: 16))")
            case .flagsChanged:
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                let isCmd = event.flags.contains(.maskCommand)
                let isCtrl = event.flags.contains(.maskControl)
                let isAlt = event.flags.contains(.maskAlternate)
                let isShift = event.flags.contains(.maskShift)
                print("[DIAGNOSTIC] Flags Changed: keyCode=\(keycode), flags=0x\(String(event.flags.rawValue, radix: 16)) (Cmd:\(isCmd) Ctrl:\(isCtrl) Alt:\(isAlt) Shift:\(isShift))")
            case .mouseMoved:
                if stateMachine.isEngaged {
                    let dx = event.getDoubleValueField(.mouseEventDeltaX)
                    let dy = event.getDoubleValueField(.mouseEventDeltaY)
                    print("[DIAGNOSTIC] Mouse Moved while Engaged: dx=\(dx), dy=\(dy)")
                }
            default:
                break
            }
        }

        // 1. Magic Thumb Button handling (Logitech hardware fallback: Cmd+Option+Tab macro)
        switch type {
        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 48 && event.flags.contains(.maskCommand) && event.flags.contains(.maskAlternate) {
                if !isPaused {
                    let windowMs = ConfigManager.shared.activeConfig.gestureWindowMs ?? 200.0
                    _ = stateMachine.handleMagicDown(windowDurationMs: windowMs)
                }
                clearSystemModifiers()
                return nil // ALWAYS SWALLOW Tab key completely (even if paused, prevents VS Code focus stealing)
            }
        case .keyUp:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 48 {
                return nil // ALWAYS SWALLOW Tab key release
            }
        case .flagsChanged:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if stateMachine.isEngaged && (keycode == 55 || keycode == 58 || keycode == 0) {
                return nil // SWALLOW modifier changes while magic gesture window is active
            }
        case .mouseMoved:
            if stateMachine.isEngaged {
                let dx = event.getDoubleValueField(.mouseEventDeltaX)
                let dy = event.getDoubleValueField(.mouseEventDeltaY)
                _ = stateMachine.handleMouseDragged(deltaX: dx, deltaY: dy)
                return nil // SWALLOW movement while gesture is engaged so cursor stays in place
            }
            return Unmanaged.passRetained(event)
        default:
            break
        }

        if isPaused {
            return Unmanaged.passRetained(event)
        }

        // 2. Standard multi-button mouse handling (Buttons 3, 4, 5, etc.)
        switch type {
        case .otherMouseDown:
            let shouldSuppress = stateMachine.handleButtonDown(buttonNumber: buttonNumber)
            return shouldSuppress ? nil : Unmanaged.passRetained(event)
        case .otherMouseDragged:
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            let shouldSuppress = stateMachine.handleMouseDragged(deltaX: dx, deltaY: dy)
            return shouldSuppress ? nil : Unmanaged.passRetained(event)
        case .otherMouseUp:
            let shouldSuppress = stateMachine.handleButtonUp(buttonNumber: buttonNumber)
            return shouldSuppress ? nil : Unmanaged.passRetained(event)
        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    private func clearSystemModifiers() {
        if let clearEvent = CGEvent(source: nil) {
            clearEvent.type = .flagsChanged
            clearEvent.flags = []
            clearEvent.post(tap: .cghidEventTap)
        }
    }
}
