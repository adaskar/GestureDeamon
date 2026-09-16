import Cocoa
import SwiftUI

public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = PreferencesWindowController()
    public static let windowFocusDidChangeNotification = Notification.Name("PreferencesWindowFocusDidChange")

    private var preferencesWindow: NSWindow?
    private var appActiveObserver: NSObjectProtocol?
    private var appResignObserver: NSObjectProtocol?

    public var isPreferencesWindowKey: Bool {
        guard let window = preferencesWindow else { return false }
        return window.isKeyWindow && NSApp.isActive
    }

    private init() {
        super.init(window: nil)
        setupAppObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupAppObservers() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.notifyFocusChange()
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleAppResignedActive()
        }
    }

    private func notifyFocusChange() {
        NotificationCenter.default.post(name: PreferencesWindowController.windowFocusDidChangeNotification, object: nil)
    }

    private func handleAppResignedActive() {
        EventTapManager.shared.isCalibrationMode = false
        EventTapManager.shared.stopRecordingShortcut()
        EventTapManager.shared.resetState()
        notifyFocusChange()
    }

    public func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let window = self.preferencesWindow {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                self.notifyFocusChange()
                return
            }

            let rootView = PreferencesView()
            let hostingController = NSHostingController(rootView: rootView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "GestureDaemon Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 780, height: 560)
            window.setContentSize(NSSize(width: 820, height: 620))
            window.center()
            window.setFrameAutosaveName("GestureDaemonPreferencesWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self

            self.preferencesWindow = window
            self.window = window

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            self.notifyFocusChange()
        }
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        notifyFocusChange()
    }

    public func windowDidResignKey(_ notification: Notification) {
        EventTapManager.shared.isCalibrationMode = false
        EventTapManager.shared.stopRecordingShortcut()
        EventTapManager.shared.resetState()
        notifyFocusChange()
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        EventTapManager.shared.isCalibrationMode = false
        EventTapManager.shared.stopRecordingShortcut()
        EventTapManager.shared.resetState()
        notifyFocusChange()
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        notifyFocusChange()
    }

    public func windowWillClose(_ notification: Notification) {
        EventTapManager.shared.isCalibrationMode = false
        EventTapManager.shared.stopRecordingShortcut()
        EventTapManager.shared.resetState()
        notifyFocusChange()
    }

    deinit {
        if let obs = appActiveObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = appResignObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

