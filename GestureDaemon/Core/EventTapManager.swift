import Cocoa
import CoreGraphics

public final class EventTapManager {
    public static let shared = EventTapManager()

    private var primaryEventTap: CFMachPort?
    private var primaryRunLoopSource: CFRunLoopSource?

    private var motionEventTap: CFMachPort?
    private var motionRunLoopSource: CFRunLoopSource?

    private let stateMachine = GestureStateMachine()
    private var diagnosticMode = false
    public var isPaused: Bool = false {
        didSet {
            if isPaused {
                resetState()
            } else {
                ensureTapActive()
            }
        }
    }

    private var isLogitechMacroActive = false
    private var cmdReleased = false
    private var optReleased = false
    private var macroSafetyTimer: DispatchSourceTimer?

    // Active shortcut recording session in Preferences UI
    public struct ShortcutRecordingSession {
        public let onCapture: (UInt16, [String]) -> Void
        public let onFlagsChanged: ([String]) -> Void
        public let onCancel: () -> Void
        public let onClear: () -> Void
    }

    private var activeRecordingSession: ShortcutRecordingSession?
    private var lastRecordedKeyCode: Int64?

    public func startRecordingShortcut(
        onCapture: @escaping (UInt16, [String]) -> Void,
        onFlagsChanged: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self.activeRecordingSession = ShortcutRecordingSession(
            onCapture: onCapture,
            onFlagsChanged: onFlagsChanged,
            onCancel: onCancel,
            onClear: onClear
        )
        self.lastRecordedKeyCode = nil
        ensureTapActive()
    }

    public func stopRecordingShortcut() {
        self.activeRecordingSession = nil
        self.lastRecordedKeyCode = nil
    }

    public var isRecordingShortcutActive: Bool {
        return activeRecordingSession != nil
    }

    public var isCalibrationMode: Bool {
        get { stateMachine.isCalibrationMode }
        set {
            stateMachine.isCalibrationMode = newValue
            if !newValue {
                stateMachine.reset()
                stopMotionTap()
            }
        }
    }

    public var onCalibrationEvent: ((CalibrationEvent) -> Void)? {
        get { stateMachine.onCalibrationEvent }
        set { stateMachine.onCalibrationEvent = newValue }
    }

    private init() {
        stateMachine.onEngagementChanged = { [weak self] engaged in
            self?.setMotionTrackingEnabled(engaged)
        }
    }

    public func enableDiagnostics(_ enabled: Bool) {
        self.diagnosticMode = enabled
    }

    public func handleHIDPlusPlusGesture(pressed: Bool) {
        if isPaused { return }
        if pressed {
            _ = stateMachine.handleMagicDown(isMacro: false)
        } else {
            _ = stateMachine.handleMagicUp()
        }
    }

    public func setMotionTrackingEnabled(_ enabled: Bool) {
        if enabled {
            startMotionTap()
        } else {
            stopMotionTap()
        }
    }

    public func start() {
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Primary tap: buttons, keys, modifiers.
        // mouseMoved is NEVER in primaryMask so normal mouse/trackpad motion has ZERO CPU overhead!
        var primaryMask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
                                     | (1 << CGEventType.otherMouseUp.rawValue)
                                     | (1 << CGEventType.otherMouseDragged.rawValue)
                                     | (1 << CGEventType.keyDown.rawValue)
                                     | (1 << CGEventType.keyUp.rawValue)
                                     | (1 << CGEventType.flagsChanged.rawValue)

        if diagnosticMode {
            primaryMask |= (1 << CGEventType.leftMouseDown.rawValue)
                        | (1 << CGEventType.leftMouseUp.rawValue)
                        | (1 << CGEventType.rightMouseDown.rawValue)
                        | (1 << CGEventType.rightMouseUp.rawValue)
        }

        guard let pTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: primaryMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handlePrimaryEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            Log.error("Failed to create primary CGEventTap. Check Accessibility permission.")
            return
        }

        self.primaryEventTap = pTap
        let pSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, pTap, 0)
        self.primaryRunLoopSource = pSource
        CFRunLoopAddSource(CFRunLoopGetMain(), pSource, .commonModes)
        CGEvent.tapEnable(tap: pTap, enable: true)

        Log.info("Primary event tap engaged (zero motion overhead).")
    }

    private func startMotionTap() {
        guard motionEventTap == nil else { return }
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let motionMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
                                     | (1 << CGEventType.scrollWheel.rawValue)

        guard let mTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: motionMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleMotionEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            Log.error("Failed to create dynamic motion CGEventTap.")
            return
        }

        self.motionEventTap = mTap
        let mSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mTap, 0)
        self.motionRunLoopSource = mSource
        CFRunLoopAddSource(CFRunLoopGetMain(), mSource, .commonModes)
        CGEvent.tapEnable(tap: mTap, enable: true)
    }

    private func stopMotionTap() {
        guard let mTap = motionEventTap else { return }
        CGEvent.tapEnable(tap: mTap, enable: false)
        if let mSource = motionRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mSource, .commonModes)
        }
        CFMachPortInvalidate(mTap)
        self.motionEventTap = nil
        self.motionRunLoopSource = nil
    }

    public func stop() {
        if let tap = primaryEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = primaryRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        self.primaryEventTap = nil
        self.primaryRunLoopSource = nil
        stopMotionTap()
        Log.info("Event taps disconnected.")
    }

    private func handlePrimaryEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.info("Primary EventTap disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input/sleep")). Re-enabling...")
            if let tap = primaryEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        // Intercept and swallow keystrokes during active shortcut recording in Preferences UI
        // This prevents macOS system hotkeys (like Ctrl+Down for App Exposé or Ctrl+Up for Mission Control) from triggering!
        if let session = activeRecordingSession {
            if type == .flagsChanged {
                let mods = KeyCodeHelper.modifiersFromNSEventFlags(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
                session.onFlagsChanged(mods)
                return Unmanaged.passRetained(event)
            } else if type == .keyDown {
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                if keycode == 53 { // Escape cancels recording
                    activeRecordingSession = nil
                    session.onCancel()
                    return nil // SWALLOW Escape
                }
                let mods = KeyCodeHelper.modifiersFromNSEventFlags(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
                if keycode == 51 && mods.isEmpty { // Bare Delete/Backspace clears
                    activeRecordingSession = nil
                    session.onClear()
                    return nil // SWALLOW Delete
                }
                lastRecordedKeyCode = keycode
                activeRecordingSession = nil
                session.onCapture(UInt16(keycode), mods)
                return nil // SWALLOW KEY DOWN: Prevents macOS system shortcuts (Exposé, Mission Control, etc.) from firing!
            } else if type == .keyUp {
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                if keycode == lastRecordedKeyCode || keycode == 53 || keycode == 51 {
                    lastRecordedKeyCode = nil
                    return nil // SWALLOW KEY UP
                }
            }
        }

        if diagnosticMode {
            switch type {
            case .otherMouseDown, .otherMouseUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
                let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
                print("[DIAGNOSTIC] Mouse Event: type=\(type.rawValue), buttonNumber=\(buttonNumber)")
                fflush(stdout)
            case .keyDown, .keyUp:
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                print("[DIAGNOSTIC] Keyboard Event: type=\(type.rawValue), keyCode=\(keycode), flags=0x\(String(event.flags.rawValue, radix: 16))")
                fflush(stdout)
            case .flagsChanged:
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                let isCmd = event.flags.contains(.maskCommand)
                let isCtrl = event.flags.contains(.maskControl)
                let isAlt = event.flags.contains(.maskAlternate)
                let isShift = event.flags.contains(.maskShift)
                print("[DIAGNOSTIC] Flags Changed: keyCode=\(keycode), flags=0x\(String(event.flags.rawValue, radix: 16)) (Cmd:\(isCmd) Ctrl:\(isCtrl) Alt:\(isAlt) Shift:\(isShift))")
                fflush(stdout)
            default:
                break
            }
        }

        // 1. Magic Thumb Button handling (Logitech hardware fallback: Cmd+Option+Tab macro)
        switch type {
        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 48 && event.flags.contains(.maskCommand) && event.flags.contains(.maskAlternate) {
                isLogitechMacroActive = true
                cmdReleased = false
                optReleased = false

                macroSafetyTimer?.cancel()
                let safetyTimer = DispatchSource.makeTimerSource(queue: .main)
                safetyTimer.schedule(deadline: .now() + 1.5)
                safetyTimer.setEventHandler { [weak self] in
                    guard let self = self, self.isLogitechMacroActive else { return }
                    self.isLogitechMacroActive = false
                    self.clearSystemModifiers()
                }
                safetyTimer.resume()
                self.macroSafetyTimer = safetyTimer

                if !isPaused {
                    let windowMs = ConfigManager.shared.activeConfig.gestureWindowMs ?? 200.0
                    _ = stateMachine.handleMagicDown(isMacro: true, windowDurationMs: windowMs)
                }
                clearSystemModifiers()
                return nil // ALWAYS SWALLOW Tab key completely (even if paused, prevents VS Code focus stealing)
            }
        case .keyUp:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 48 && (isLogitechMacroActive || stateMachine.isEngaged) {
                return nil // Swallow Tab key release only when Logitech macro or gesture was active
            }
        case .flagsChanged:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if isLogitechMacroActive && (keycode == 55 || keycode == 58) {
                let hadCommand = event.flags.contains(.maskCommand)
                let hadAlternate = event.flags.contains(.maskAlternate)

                // Strip Command & Option from flags so WindowServer & apps never see them active
                event.flags.remove([.maskCommand, .maskAlternate])

                if keycode == 55 { cmdReleased = true }
                if keycode == 58 { optReleased = true }

                if (!hadCommand && !hadAlternate) || (cmdReleased && optReleased) {
                    isLogitechMacroActive = false
                    macroSafetyTimer?.cancel()
                    macroSafetyTimer = nil
                    clearSystemModifiers()
                }
                return Unmanaged.passRetained(event)
            }
        default:
            break
        }

        if isPaused {
            return Unmanaged.passRetained(event)
        }

        // 2. Standard multi-button mouse handling (Buttons 3, 4, 5, etc.)
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        let config = ConfigManager.shared.activeConfig

        // In Calibration Mode (Live Tester), intercept all non-trigger buttons for live testing
        if isCalibrationMode && buttonNumber != config.triggerButtonIndex {
            let backIndex = config.backButtonIndex ?? 3
            let forwardIndex = config.forwardButtonIndex ?? 4

            if buttonNumber == backIndex {
                if type == .otherMouseDown {
                    let action = ConfigManager.shared.effectiveAction(for: .backButton)
                    let label = action?.comment ?? "Universal Back (⌘[)"
                    onCalibrationEvent?(.otherButton(buttonIndex: Int(backIndex), isDown: true, actionName: label))
                } else if type == .otherMouseUp {
                    onCalibrationEvent?(.otherButton(buttonIndex: Int(backIndex), isDown: false, actionName: nil))
                }
                return nil
            } else if buttonNumber == forwardIndex {
                if type == .otherMouseDown {
                    let action = ConfigManager.shared.effectiveAction(for: .forwardButton)
                    let label = action?.comment ?? "Universal Forward (⌘])"
                    onCalibrationEvent?(.otherButton(buttonIndex: Int(forwardIndex), isDown: true, actionName: label))
                } else if type == .otherMouseUp {
                    onCalibrationEvent?(.otherButton(buttonIndex: Int(forwardIndex), isDown: false, actionName: nil))
                }
                return nil
            } else {
                let label = buttonNumber == 2 ? "Middle Click" : "Button \(buttonNumber)"
                if type == .otherMouseDown {
                    onCalibrationEvent?(.otherButton(buttonIndex: Int(buttonNumber), isDown: true, actionName: label))
                } else if type == .otherMouseUp {
                    onCalibrationEvent?(.otherButton(buttonIndex: Int(buttonNumber), isDown: false, actionName: nil))
                }
                return nil
            }
        }

        // 3. Side Navigation Buttons (Back & Forward) in normal operation
        if (config.enableSideButtons ?? true) && buttonNumber != config.triggerButtonIndex {
            let backIndex = config.backButtonIndex ?? 3
            let forwardIndex = config.forwardButtonIndex ?? 4

            if buttonNumber == backIndex {
                if type == .otherMouseDown {
                    let customAction = ConfigManager.shared.effectiveAction(for: .backButton)
                    Log.info("🖱️ [BACK BUTTON] Clicked (Button \(buttonNumber)). Action: \(customAction != nil ? "Profile Override (KeyCode: \(customAction?.keyCode ?? 0), Mods: \(customAction?.modifiers ?? []))" : "Universal Default (Cmd+[)")")

                    if let action = customAction {
                        ActionDispatcher.shared.dispatch(action: action)
                    } else {
                        ActionDispatcher.shared.dispatchNavigationBack()
                    }
                }
                return nil // Swallow down, up, and drag for side navigation button
            } else if buttonNumber == forwardIndex {
                if type == .otherMouseDown {
                    let customAction = ConfigManager.shared.effectiveAction(for: .forwardButton)
                    Log.info("🖱️ [FORWARD BUTTON] Clicked (Button \(buttonNumber)). Action: \(customAction != nil ? "Profile Override (KeyCode: \(customAction?.keyCode ?? 0), Mods: \(customAction?.modifiers ?? []))" : "Universal Default (Cmd+])")")

                    if let action = customAction {
                        ActionDispatcher.shared.dispatch(action: action)
                    } else {
                        ActionDispatcher.shared.dispatchNavigationForward()
                    }
                }
                return nil // Swallow down, up, and drag for side navigation button
            }
        }

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

    private func handleMotionEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let tap = motionEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }
        if type == .tapDisabledByUserInput {
            return Unmanaged.passRetained(event)
        }

        guard stateMachine.isEngaged else {
            stopMotionTap()
            return Unmanaged.passRetained(event)
        }

        if type == .scrollWheel {
            let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            if deltaY != 0 {
                _ = stateMachine.handleScrollWheel(deltaY: deltaY)
            }
            return nil // Swallow scroll wheel event while thumb button is engaged
        }

        guard type == .mouseMoved else {
            return Unmanaged.passRetained(event)
        }

        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)

        if diagnosticMode {
            print("[DIAGNOSTIC] Mouse Moved while Engaged: dx=\(dx), dy=\(dy)")
        }

        _ = stateMachine.handleMouseDragged(deltaX: dx, deltaY: dy)
        return nil // Swallow movement while gesture is engaged so cursor stays in place
    }

    public func ensureTapActive() {
        if let tap = primaryEventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                Log.info("Primary EventTap was inactive. Re-enabling...")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            Log.info("Primary EventTap missing. Starting...")
            start()
        }
    }

    public func resetState() {
        macroSafetyTimer?.cancel()
        macroSafetyTimer = nil
        isLogitechMacroActive = false
        cmdReleased = false
        optReleased = false
        stateMachine.reset()
        stopMotionTap()
        clearSystemModifiers()
    }

    public func clearSystemModifiers() {
        if let clearEvent = CGEvent(source: nil) {
            clearEvent.type = .flagsChanged
            clearEvent.flags = []
            clearEvent.post(tap: .cghidEventTap)
        }
    }
}
