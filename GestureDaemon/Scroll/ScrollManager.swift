import Cocoa
import CoreGraphics

public final class ScrollManager {
    public static let shared = ScrollManager()

    public private(set) var isActive = false

    private var scrollTap: CFMachPort?
    private var scrollRunLoopSource: CFRunLoopSource?

    private var mouseTap: CFMachPort?
    private var mouseRunLoopSource: CFRunLoopSource?

    private var hotkeyTap: CFMachPort?
    private var hotkeyRunLoopSource: CFRunLoopSource?

    // Modifier key tracking
    private var isDashActive = false
    private var isToggleActive = false
    private var isBlockActive = false

    // Remote desktop bundle identifiers / executable keywords to bypass smoothing
    private static let remoteDesktopBundleIdentifiers: Set<String> = [
        "com.teamviewer.TeamViewer",
        "com.teamviewer.TeamViewerHost",
        "com.anydesk.anydesk",
        "com.parsec.www",
        "com.rustdesk.RustDesk",
        "com.microsoft.rdc.macos",
        "com.realvnc.vncviewer",
        "com.tigervnc.vncviewer",
        "com.netease.uuremote"
    ]

    private static let remoteDesktopExecutableKeywords = [
        "screensharingd",
        "ScreensharingAgent",
        "ARDAgent"
    ]

    private var cachedTargetPid: pid_t = 0
    private var cachedTargetBundleId: String? = nil

    private init() {
        NotificationCenter.default.addObserver(
            forName: ConfigManager.configDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWithConfig()
        }
    }

    public func syncWithConfig() {
        let isEnabled = ConfigManager.shared.activeConfig.smoothScroll?.enabled ?? false
        if isEnabled && !isActive {
            start()
        } else if !isEnabled && isActive {
            stop()
        }
    }

    public func start() {
        guard !isActive else { return }
        let isEnabled = ConfigManager.shared.activeConfig.smoothScroll?.enabled ?? false
        guard isEnabled else { return }

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // 1. Dedicated Scroll Wheel Event Tap at .cgAnnotatedSessionEventTap / .tailAppendEventTap
        let scrollMask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
        guard let sTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleScrollEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleScrollEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            Log.error("ScrollManager: Failed to create scrollEventTap.")
            return
        }

        self.scrollTap = sTap
        let sSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, sTap, 0)
        self.scrollRunLoopSource = sSource
        CFRunLoopAddSource(CFRunLoopGetMain(), sSource, .commonModes)
        CGEvent.tapEnable(tap: sTap, enable: true)

        // 2. Passive Left Mouse Down Tap for instant scroll braking (.listenOnly)
        let mouseMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        if let mTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mouseMask,
            callback: { (_, _, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.brake()
                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        ) {
            self.mouseTap = mTap
            let mSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mTap, 0)
            self.mouseRunLoopSource = mSource
            CFRunLoopAddSource(CFRunLoopGetMain(), mSource, .commonModes)
            CGEvent.tapEnable(tap: mTap, enable: true)
        }

        // 3. Passive Flags Changed Tap for modifier shortcuts (.listenOnly)
        let hotkeyMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        if let hTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: hotkeyMask,
            callback: { (_, _, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                manager.updateModifiers(flags: flags)
                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        ) {
            self.hotkeyTap = hTap
            let hSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hTap, 0)
            self.hotkeyRunLoopSource = hSource
            CFRunLoopAddSource(CFRunLoopGetMain(), hSource, .commonModes)
            CGEvent.tapEnable(tap: hTap, enable: true)
        }

        isActive = true
        ScrollPoster.shared.create()
        ScrollPoster.shared.startKeeper()
        Log.info("ScrollManager started with dedicated .cgAnnotatedSessionEventTap.")
    }

    public func stop() {
        guard isActive else { return }
        isActive = false

        if let tap = scrollTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = scrollRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        scrollTap = nil
        scrollRunLoopSource = nil

        if let tap = mouseTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = mouseRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        mouseTap = nil
        mouseRunLoopSource = nil

        if let tap = hotkeyTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = hotkeyRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        hotkeyTap = nil
        hotkeyRunLoopSource = nil

        ScrollPoster.shared.stop()
        ScrollPoster.shared.stopKeeper()
        ScrollPoster.shared.reset()
        Log.info("ScrollManager completely stopped and all scroll taps destroyed.")
    }

    public func brake() {
        ScrollPoster.shared.brake()
    }

    public func updateModifiers(flags: NSEvent.ModifierFlags) {
        let config = ConfigManager.shared.activeConfig.smoothScroll ?? SmoothScrollConfig()

        isDashActive = matchesModifier(config.dashModifier, in: flags)
        let toggleState = matchesModifier(config.toggleModifier, in: flags)
        if toggleState != isToggleActive {
            isToggleActive = toggleState
            ScrollPoster.shared.updateShifting(enable: toggleState)
        }
        isBlockActive = matchesModifier(config.blockModifier, in: flags)
    }

    private func matchesModifier(_ modifierName: String?, in flags: NSEvent.ModifierFlags) -> Bool {
        guard let name = modifierName?.lowercased(), !name.isEmpty else { return false }
        switch name {
        case "option", "opt", "alt":
            return flags.contains(.option)
        case "shift":
            return flags.contains(.shift)
        case "command", "cmd":
            return flags.contains(.command)
        case "control", "ctrl":
            return flags.contains(.control)
        default:
            return false
        }
    }

    private func handleScrollEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = scrollTap { CGEvent.tapEnable(tap: tap, enable: true) }
            ScrollPoster.shared.stop(.trackingEnd)
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        // Skip synthetic events synthesized by GestureDaemon
        if ScrollDispatchContext.isSyntheticSmoothEvent(event) {
            return Unmanaged.passUnretained(event)
        }

        // Skip if thumb button is held down (EventTapManager motionTap handles thumb + scroll for volume)
        if EventTapManager.shared.isPaused {
            return Unmanaged.passUnretained(event)
        }

        let globalConfig = ConfigManager.shared.activeConfig.smoothScroll ?? SmoothScrollConfig()
        guard globalConfig.enabled else {
            return Unmanaged.passUnretained(event)
        }

        // If Block modifier is held (e.g. Command for CAD/zoom), pass raw event through
        if isBlockActive {
            return Unmanaged.passUnretained(event)
        }

        let scrollEvent = ScrollEvent(with: event)
        let hasVerticalDelta = scrollEvent.yData.valid && scrollEvent.yData.usableValue != 0.0
        let hasHorizontalDelta = scrollEvent.xData.valid && scrollEvent.xData.usableValue != 0.0

        guard hasVerticalDelta || hasHorizontalDelta else {
            return Unmanaged.passUnretained(event)
        }

        // Pass native trackpads and Magic Mouse through untouched!
        if scrollEvent.isTrackpad() {
            return Unmanaged.passUnretained(event)
        }

        // Detect target application
        let targetPid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        let targetBundleId = resolveBundleIdentifier(for: targetPid)

        // Check if event is from remote desktop application
        if isRemoteControlApplication(event: event, targetPid: targetPid, bundleId: targetBundleId) {
            return Unmanaged.passUnretained(event)
        }

        // Check per-application profile overrides
        if let bundleId = targetBundleId,
           let appProfile = ConfigManager.shared.activeConfig.applications?[bundleId],
           let profileSmoothEnabled = appProfile.smoothScrollEnabled,
           !profileSmoothEnabled {
            // App explicitly disabled smooth scrolling (e.g. Blender, games, etc.)
            return Unmanaged.passUnretained(event)
        }

        // Smooth configuration parameters
        let enableSmooth = globalConfig.enabled
        let enableSmoothVertical = globalConfig.smoothVertical
        let enableSmoothHorizontal = globalConfig.smoothHorizontal
        let enableReverseVertical = globalConfig.reverseVertical
        let enableReverseHorizontal = globalConfig.reverseHorizontal

        let step = globalConfig.step
        let speed = globalConfig.speed
        let duration = globalConfig.durationTransition
        let deadZone = globalConfig.deadZone
        let simulateTrackpad = globalConfig.simulateTrackpad

        let willShiftVerticalToHorizontal = isToggleActive && hasVerticalDelta && !hasHorizontalDelta
        let verticalReversePreference = willShiftVerticalToHorizontal ? enableReverseHorizontal : enableReverseVertical

        if hasVerticalDelta && verticalReversePreference {
            ScrollEvent.reverseY(scrollEvent)
        }
        if hasHorizontalDelta && enableReverseHorizontal {
            ScrollEvent.reverseX(scrollEvent)
        }

        let verticalPreference = willShiftVerticalToHorizontal ? enableSmoothHorizontal : enableSmoothVertical
        var shouldSmoothVertical = hasVerticalDelta && verticalPreference
        var shouldSmoothHorizontal = hasHorizontalDelta && enableSmoothHorizontal

        if !enableSmooth {
            shouldSmoothVertical = false
            shouldSmoothHorizontal = false
        }

        var smoothedY = 0.0
        var smoothedX = 0.0

        if shouldSmoothVertical {
            if scrollEvent.yData.usableValue.magnitude < step {
                ScrollEvent.normalizeY(scrollEvent, threshold: step)
            }
            smoothedY = scrollEvent.yData.usableValue
        }

        if shouldSmoothHorizontal {
            if scrollEvent.xData.usableValue.magnitude < step {
                ScrollEvent.normalizeX(scrollEvent, threshold: step)
            }
            smoothedX = scrollEvent.xData.usableValue
        }

        let needVerticalPassthrough = hasVerticalDelta && !shouldSmoothVertical
        let needHorizontalPassthrough = hasHorizontalDelta && !shouldSmoothHorizontal
        let needsPassthrough = needVerticalPassthrough || needHorizontalPassthrough
        let shouldSmoothAny = (smoothedY != 0.0) || (smoothedX != 0.0)

        let amplification = isDashActive ? 5.0 : 1.0

        if shouldSmoothAny {
            ScrollPoster.shared.update(
                event: event,
                durationTransition: duration,
                y: smoothedY,
                x: smoothedX,
                speed: speed,
                deadZone: deadZone,
                simulateTrackpad: simulateTrackpad,
                amplification: amplification
            ).tryStart()
        }

        if needsPassthrough {
            if shouldSmoothVertical {
                ScrollEvent.clearY(scrollEvent)
            }
            if shouldSmoothHorizontal {
                ScrollEvent.clearX(scrollEvent)
            }
            return Unmanaged.passUnretained(event)
        }

        if shouldSmoothAny {
            if ScrollPoster.shared.isAvailable {
                return nil // Swallow raw discrete wheel event!
            } else {
                return Unmanaged.passUnretained(event)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func resolveBundleIdentifier(for pid: pid_t) -> String? {
        guard pid > 1 else {
            return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        if pid == cachedTargetPid, let bundleId = cachedTargetBundleId {
            return bundleId
        }
        cachedTargetPid = pid
        if let app = NSRunningApplication(processIdentifier: pid) {
            cachedTargetBundleId = app.bundleIdentifier
        } else {
            cachedTargetBundleId = nil
        }
        return cachedTargetBundleId
    }

    private func isRemoteControlApplication(event: CGEvent, targetPid: pid_t, bundleId: String?) -> Bool {
        let sourcePid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        let checkPid = sourcePid > 0 ? sourcePid : targetPid
        guard checkPid > 0, let app = NSRunningApplication(processIdentifier: checkPid) else { return false }

        if let bId = app.bundleIdentifier, Self.remoteDesktopBundleIdentifiers.contains(bId) {
            return true
        }

        if let path = app.executableURL?.path {
            for keyword in Self.remoteDesktopExecutableKeywords {
                if path.contains(keyword) {
                    return true
                }
            }
        }
        return false
    }
}
