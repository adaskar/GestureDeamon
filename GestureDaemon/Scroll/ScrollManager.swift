import Cocoa
import CoreGraphics
import os

public final class ScrollManager {
    public static let shared = ScrollManager()

    public private(set) var isActive = false

    private var scrollTap: CFMachPort?
    private var scrollRunLoopSource: CFRunLoopSource?

    // Fast O(1) process cache to avoid repeated LaunchServices/NSRunningApplication IPCs
    private struct AppProfileCacheEntry {
        let isRemote: Bool
        let isDisabled: Bool
    }
    private var appCache: [pid_t: AppProfileCacheEntry] = [:]
    private var cacheLock = os_unfair_lock_s()

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

    private init() {
        NotificationCenter.default.addObserver(
            forName: ConfigManager.configDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.cacheLock)
            self.appCache.removeAll(keepingCapacity: true)
            os_unfair_lock_unlock(&self.cacheLock)
            self.syncWithConfig()
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

        // Dedicated Scroll Wheel Event Tap at .cgAnnotatedSessionEventTap / .tailAppendEventTap
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

        ScrollPoster.shared.stop()
        ScrollPoster.shared.stopKeeper()
        ScrollPoster.shared.reset()
        os_unfair_lock_lock(&cacheLock)
        appCache.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&cacheLock)
        Log.info("ScrollManager completely stopped and scroll tap destroyed.")
    }

    public func brake() {
        ScrollPoster.shared.brake()
    }

    @inline(__always)
    private func matchesModifier(_ modifierName: String?, in flags: CGEventFlags) -> Bool {
        guard let name = modifierName?.lowercased(), !name.isEmpty else { return false }
        switch name {
        case "option", "opt", "alt":
            return flags.contains(.maskAlternate)
        case "shift":
            return flags.contains(.maskShift)
        case "command", "cmd":
            return flags.contains(.maskCommand)
        case "control", "ctrl":
            return flags.contains(.maskControl)
        default:
            return false
        }
    }

    private func handleScrollEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type != .scrollWheel {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = scrollTap { CGEvent.tapEnable(tap: tap, enable: true) }
                ScrollPoster.shared.stop(.trackingEnd)
            }
            return Unmanaged.passUnretained(event)
        }

        // 1. FAST EXIT FOR SYNTHETIC SMOOTH TICKS GENERATED BY SCROLLPOSTER
        if ScrollDispatchContext.isSyntheticSmoothEvent(event) {
            return Unmanaged.passUnretained(event)
        }

        // 2. ULTRA-FAST TRACKPAD & CONTINUOUS FILTER (ZERO ALLOCATION, < 0.0001 ms):
        // Native Apple trackpads and Magic Mouse report isContinuous != 0, active phases,
        // or subpixel float movement without integer lines.
        if ScrollEvent.isTrackpad(with: event) {
            return Unmanaged.passUnretained(event)
        }

        if EventTapManager.shared.isPaused {
            return Unmanaged.passUnretained(event)
        }

        let globalConfig = ConfigManager.shared.activeConfig.smoothScroll ?? SmoothScrollConfig()
        guard globalConfig.enabled else {
            return Unmanaged.passUnretained(event)
        }

        // Modifier shortcuts evaluated directly from event flags (zero background taps required!)
        let flags = event.flags
        let isBlock = matchesModifier(globalConfig.blockModifier, in: flags)
        if isBlock {
            return Unmanaged.passUnretained(event)
        }

        var scrollEvent = ScrollEvent(with: event)
        let hasVerticalDelta = scrollEvent.yData.valid && scrollEvent.yData.usableValue != 0.0
        let hasHorizontalDelta = scrollEvent.xData.valid && scrollEvent.xData.usableValue != 0.0

        guard hasVerticalDelta || hasHorizontalDelta else {
            return Unmanaged.passUnretained(event)
        }

        // Fast Target Application / Remote Desktop Check with O(1) Cache
        let targetPid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if targetPid > 1 {
            os_unfair_lock_lock(&cacheLock)
            let cached = appCache[targetPid]
            os_unfair_lock_unlock(&cacheLock)
            if let cached = cached {
                if cached.isRemote || cached.isDisabled {
                    return Unmanaged.passUnretained(event)
                }
            } else {
                let entry = resolveAppProfile(for: targetPid, event: event)
                os_unfair_lock_lock(&cacheLock)
                appCache[targetPid] = entry
                os_unfair_lock_unlock(&cacheLock)
                if entry.isRemote || entry.isDisabled {
                    return Unmanaged.passUnretained(event)
                }
            }
        }

        let isDash = matchesModifier(globalConfig.dashModifier, in: flags)
        let isToggle = matchesModifier(globalConfig.toggleModifier, in: flags)
        ScrollPoster.shared.updateShifting(enable: isToggle)

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

        let willShiftVerticalToHorizontal = isToggle && hasVerticalDelta && !hasHorizontalDelta
        let verticalReversePreference = willShiftVerticalToHorizontal ? enableReverseHorizontal : enableReverseVertical

        if hasVerticalDelta && verticalReversePreference {
            ScrollEvent.reverseY(&scrollEvent)
        }
        if hasHorizontalDelta && enableReverseHorizontal {
            ScrollEvent.reverseX(&scrollEvent)
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
                ScrollEvent.normalizeY(&scrollEvent, threshold: step)
            }
            smoothedY = scrollEvent.yData.usableValue
        }

        if shouldSmoothHorizontal {
            if scrollEvent.xData.usableValue.magnitude < step {
                ScrollEvent.normalizeX(&scrollEvent, threshold: step)
            }
            smoothedX = scrollEvent.xData.usableValue
        }

        let needVerticalPassthrough = hasVerticalDelta && !shouldSmoothVertical
        let needHorizontalPassthrough = hasHorizontalDelta && !shouldSmoothHorizontal
        let needsPassthrough = needVerticalPassthrough || needHorizontalPassthrough
        let shouldSmoothAny = (smoothedY != 0.0) || (smoothedX != 0.0)

        let amplification = isDash ? 5.0 : 1.0

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
                ScrollEvent.clearY(&scrollEvent)
            }
            if shouldSmoothHorizontal {
                ScrollEvent.clearX(&scrollEvent)
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

    private func resolveAppProfile(for pid: pid_t, event: CGEvent) -> AppProfileCacheEntry {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return AppProfileCacheEntry(isRemote: false, isDisabled: false)
        }

        var isRemote = false
        if let bId = app.bundleIdentifier, Self.remoteDesktopBundleIdentifiers.contains(bId) {
            isRemote = true
        } else if let path = app.executableURL?.path {
            for keyword in Self.remoteDesktopExecutableKeywords {
                if path.contains(keyword) {
                    isRemote = true
                    break
                }
            }
        }

        var isDisabled = false
        if let bId = app.bundleIdentifier,
           let profile = ConfigManager.shared.activeConfig.applications?[bId],
           profile.smoothScrollEnabled == false {
            isDisabled = true
        }

        return AppProfileCacheEntry(isRemote: isRemote, isDisabled: isDisabled)
    }
}
