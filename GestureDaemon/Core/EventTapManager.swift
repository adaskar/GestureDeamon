import Cocoa
import CoreGraphics

public final class EventTapManager {
    public static let shared = EventTapManager()

    private var primaryEventTap: CFMachPort?
    private var primaryRunLoopSource: CFRunLoopSource?

    private var motionEventTap: CFMachPort?
    private var motionRunLoopSource: CFRunLoopSource?

    // Keyboard tap — only active when needed.
    // When a HID++ device is open the mouse firmware never sends the Cmd+Opt+Tab
    // macro, so we can leave this tap OFF entirely while the user types, giving
    // zero keyboard IPC overhead.  The tap is turned on when:
    //   • No HID++ device is connected  (macro fallback path may be needed)
    //   • A shortcut-recording session is open in Preferences
    //   • A Logitech macro is mid-flight (to handle modifier releases cleanly)
    private var keyboardEventTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?

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

    private var isLogitechMacroActive = false {
        didSet {
            if oldValue != isLogitechMacroActive {
                updateKeyboardTapState()
            }
        }
    }
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
        updateKeyboardTapState() // Recording session always needs keyboard tap
    }

    public func stopRecordingShortcut() {
        self.activeRecordingSession = nil
        self.lastRecordedKeyCode = nil
        updateKeyboardTapState() // May now be able to stop keyboard tap
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

        // Watch for HID++ device connection / disconnection so we can turn the
        // keyboard tap on/off automatically.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHIDCapabilitiesChanged),
            name: .hidHardwareCapabilitiesDidChange,
            object: nil
        )
    }

    @objc private func handleHIDCapabilitiesChanged() {
        updateKeyboardTapState()
    }

    // MARK: - Keyboard tap lifecycle

    /// Decides whether the keyboard tap should be running and starts/stops it.
    /// Rules:
    ///   ON  – no HID++ device open (macro fallback may fire)
    ///   ON  – shortcut recording session is active
    ///   ON  – a Logitech macro is currently mid-flight
    ///   OFF – HID++ device is open AND no recording AND no active macro
    private func updateKeyboardTapState() {
        let needsKeyboard = !HIDPlusPlusManager.shared.isDeviceOpen
                         || activeRecordingSession != nil
                         || isLogitechMacroActive
        if needsKeyboard {
            startKeyboardTap()
        } else {
            stopKeyboardTap()
        }
    }

    private func startKeyboardTap() {
        guard keyboardEventTap == nil else { return }
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let keyMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                                 | (1 << CGEventType.keyUp.rawValue)
                                 | (1 << CGEventType.flagsChanged.rawValue)

        guard let kTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleKeyboardEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            Log.error("Failed to create keyboard CGEventTap.")
            return
        }

        self.keyboardEventTap = kTap
        let kSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, kTap, 0)
        self.keyboardRunLoopSource = kSource
        CFRunLoopAddSource(CFRunLoopGetMain(), kSource, .commonModes)
        CGEvent.tapEnable(tap: kTap, enable: true)
        Log.info("Keyboard event tap started (HID++ device open: \(HIDPlusPlusManager.shared.isDeviceOpen)).")
    }

    private func stopKeyboardTap() {
        guard let kTap = keyboardEventTap else { return }
        CGEvent.tapEnable(tap: kTap, enable: false)
        if let kSource = keyboardRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), kSource, .commonModes)
        }
        CFMachPortInvalidate(kTap)
        self.keyboardEventTap = nil
        self.keyboardRunLoopSource = nil
        Log.info("Keyboard event tap stopped (HID++ device open — keyboard IPC overhead eliminated).")
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

        // Primary tap: mouse buttons only.
        // keyDown/keyUp/flagsChanged have been removed — they live in the
        // separate keyboard tap that is only active when actually needed.
        // mouseMoved is also absent here (lives in the dynamic motion tap).
        // Result: zero keyboard IPC overhead while typing normally.
        var primaryMask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
                                     | (1 << CGEventType.otherMouseUp.rawValue)
                                     | (1 << CGEventType.otherMouseDragged.rawValue)

        if diagnosticMode {
            primaryMask |= (1 << CGEventType.leftMouseDown.rawValue)
                        | (1 << CGEventType.leftMouseUp.rawValue)
                        | (1 << CGEventType.rightMouseDown.rawValue)
                        | (1 << CGEventType.rightMouseUp.rawValue)
                        | (1 << CGEventType.keyDown.rawValue)
                        | (1 << CGEventType.keyUp.rawValue)
                        | (1 << CGEventType.flagsChanged.rawValue)
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

        Log.info("Primary event tap engaged (mouse buttons only — zero keyboard/motion overhead).")

        // Start keyboard tap only if it's currently needed.
        updateKeyboardTapState()
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
        stopKeyboardTap()
        Log.info("Event taps disconnected.")
    }

    // MARK: - Primary event handler (mouse buttons only)

    private func handlePrimaryEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.info("Primary EventTap disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input/sleep")). Re-enabling...")
            // Use ensureTapActive so we also handle the case where macOS fully
            // invalidated the CFMachPort (not just disabled it).
            ensureTapActive()
            return Unmanaged.passRetained(event)
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

        if isPaused {
            return Unmanaged.passRetained(event)
        }

        // Multi-button mouse handling (Buttons 3, 4, 5, etc.)
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

        // Side Navigation Buttons (Back & Forward) in normal operation
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

    // MARK: - Keyboard event handler (dynamic tap — only active when needed)

    private func handleKeyboardEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = keyboardEventTap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Intercept and swallow keystrokes during active shortcut recording in Preferences UI.
        // This prevents macOS system hotkeys (like Ctrl+Down for App Exposé) from triggering!
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
                    updateKeyboardTapState()
                    return nil // SWALLOW Escape
                }
                let mods = KeyCodeHelper.modifiersFromNSEventFlags(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
                if keycode == 51 && mods.isEmpty { // Bare Delete/Backspace clears
                    activeRecordingSession = nil
                    session.onClear()
                    updateKeyboardTapState()
                    return nil // SWALLOW Delete
                }
                lastRecordedKeyCode = keycode
                activeRecordingSession = nil
                session.onCapture(UInt16(keycode), mods)
                updateKeyboardTapState()
                return nil // SWALLOW KEY DOWN: Prevents macOS system shortcuts from firing!
            } else if type == .keyUp {
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                if keycode == lastRecordedKeyCode || keycode == 53 || keycode == 51 {
                    lastRecordedKeyCode = nil
                    return nil // SWALLOW KEY UP
                }
            }
        }

        if isPaused {
            return Unmanaged.passRetained(event)
        }

        // Magic Thumb Button handling (Logitech hardware fallback: Cmd+Option+Tab macro).
        // This path is only reachable when HID++ is NOT connected (keyboard tap would
        // be off otherwise), so there is no redundancy with the HID++ gesture path.
        switch type {
        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == 48 && event.flags.contains(.maskCommand) && event.flags.contains(.maskAlternate) {
                // Setting isLogitechMacroActive via the property observer triggers
                // updateKeyboardTapState(), keeping the tap alive through modifier cleanup.
                isLogitechMacroActive = true
                cmdReleased = false
                optReleased = false

                macroSafetyTimer?.cancel()
                let safetyTimer = DispatchSource.makeTimerSource(queue: .main)
                safetyTimer.schedule(deadline: .now() + 1.5)
                safetyTimer.setEventHandler { [weak self] in
                    guard let self = self, self.isLogitechMacroActive else { return }
                    self.isLogitechMacroActive = false // property observer calls updateKeyboardTapState
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
                    isLogitechMacroActive = false // property observer calls updateKeyboardTapState
                    macroSafetyTimer?.cancel()
                    macroSafetyTimer = nil
                    clearSystemModifiers()
                }
                return Unmanaged.passRetained(event)
            }
        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Motion event handler (dynamic tap — only active during gesture engagement)

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

    // MARK: - Tap health

    public func ensureTapActive() {
        if let tap = primaryEventTap {
            // Check whether the underlying CFMachPort is still valid.
            // macOS can fully invalidate (not just disable) a CGEventTap port
            // during sleep/wake cycles.  Calling tapEnable on a dead port is a
            // silent no-op, so we must detect this and rebuild from scratch.
            if !CFMachPortIsValid(tap) {
                Log.info("Primary EventTap CFMachPort is invalid (killed by macOS during sleep). Rebuilding...")
                stop()
                start()
                return
            }
            if !CGEvent.tapIsEnabled(tap: tap) {
                Log.info("Primary EventTap was inactive. Re-enabling...")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            Log.info("Primary EventTap missing. Starting...")
            start()
        }
        updateKeyboardTapState()
    }

    public func resetState() {
        macroSafetyTimer?.cancel()
        macroSafetyTimer = nil
        isLogitechMacroActive = false // property observer calls updateKeyboardTapState
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
