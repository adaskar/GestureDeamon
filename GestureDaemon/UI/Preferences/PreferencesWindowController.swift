import Cocoa
import SwiftUI

public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = PreferencesWindowController()

    private var preferencesWindow: NSWindow?

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let window = self.preferencesWindow {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
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
        }
    }

    public func windowWillClose(_ notification: Notification) {
        // Window kept in memory for instant re-opening
    }
}

