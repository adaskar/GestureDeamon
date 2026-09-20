import Cocoa
import CoreGraphics

public final class ScrollManager {
    public static let shared = ScrollManager()

    public private(set) var isActive = false

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

    private init() {}

    public func start() {
        guard !isActive else { return }
        isActive = true
        ScrollPoster.shared.create()
        ScrollPoster.shared.startKeeper()
        Log.info("ScrollManager started with CVDisplayLink display sync.")
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        ScrollPoster.shared.stop()
        ScrollPoster.shared.stopKeeper()
        Log.info("ScrollManager stopped.")
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

    /// Process incoming scroll wheel events from CGEventTap
    /// Returns: nil if event was swallowed and replaced by smooth interpolated frames,
    /// or the event if it should be passed through unmodified.
    public func handleScrollWheel(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Skip synthetic events synthesized by GestureDaemon
        if ScrollDispatchContext.isSyntheticSmoothEvent(event) {
            return Unmanaged.passRetained(event)
        }

        let globalConfig = ConfigManager.shared.activeConfig.smoothScroll ?? SmoothScrollConfig()
        guard globalConfig.enabled else {
            return Unmanaged.passRetained(event)
        }

        // If Block modifier is held (e.g. Command for CAD/zoom), pass raw event through
        if isBlockActive {
            return Unmanaged.passRetained(event)
        }

        let scrollEvent = ScrollEvent(with: event)
        let hasVerticalDelta = scrollEvent.yData.valid && scrollEvent.yData.usableValue != 0.0
        let hasHorizontalDelta = scrollEvent.xData.valid && scrollEvent.xData.usableValue != 0.0

        guard hasVerticalDelta || hasHorizontalDelta else {
            return Unmanaged.passRetained(event)
        }

        // Pass native trackpads and Magic Mouse through untouched!
        if scrollEvent.isTrackpad() {
            return Unmanaged.passRetained(event)
        }

        // Detect target application
        let targetPid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        let targetBundleId = resolveBundleIdentifier(for: targetPid)

        // Check if event is from remote desktop application
        if isRemoteControlApplication(event: event, targetPid: targetPid, bundleId: targetBundleId) {
            return Unmanaged.passRetained(event)
        }

        // Check per-application profile overrides
        if let bundleId = targetBundleId,
           let appProfile = ConfigManager.shared.activeConfig.applications?[bundleId],
           let profileSmoothEnabled = appProfile.smoothScrollEnabled,
           !profileSmoothEnabled {
            // App explicitly disabled smooth scrolling (e.g. Blender, games, etc.)
            return Unmanaged.passRetained(event)
        }

        // Smooth configuration parameters
        var enableSmooth = globalConfig.enabled
        var enableSmoothVertical = globalConfig.smoothVertical
        var enableSmoothHorizontal = globalConfig.smoothHorizontal
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
            return Unmanaged.passRetained(event)
        }

        if shouldSmoothAny {
            if ScrollPoster.shared.isAvailable {
                return nil // Swallow raw discrete wheel event!
            } else {
                return Unmanaged.passRetained(event)
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func resolveBundleIdentifier(for pid: pid_t) -> String? {
        guard pid > 1 else { return nil }
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

