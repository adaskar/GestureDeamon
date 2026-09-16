import SwiftUI
import AppKit
import Carbon

public struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: [String]?
    var onShortcutChanged: ((UInt16?, [String]?) -> Void)? = nil
    var placeholder: String = "Click to Record Shortcut"

    @State private var isRecording: Bool = false

    public init(
        keyCode: Binding<UInt16?>,
        modifiers: Binding<[String]?>,
        placeholder: String = "Click to Record Shortcut",
        onShortcutChanged: ((UInt16?, [String]?) -> Void)? = nil
    ) {
        self._keyCode = keyCode
        self._modifiers = modifiers
        self.placeholder = placeholder
        self.onShortcutChanged = onShortcutChanged
    }

    public var body: some View {
        HStack(spacing: 8) {
            ShortcutCaptureButton(
                keyCode: $keyCode,
                modifiers: $modifiers,
                isRecording: $isRecording,
                placeholder: placeholder,
                onShortcutChanged: onShortcutChanged
            )

            if keyCode != nil {
                Button(action: {
                    keyCode = nil
                    modifiers = nil
                    isRecording = false
                    onShortcutChanged?(nil, nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear shortcut")
            }
        }
    }
}

private struct ShortcutCaptureButton: NSViewRepresentable {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: [String]?
    @Binding var isRecording: Bool
    var placeholder: String
    var onShortcutChanged: ((UInt16?, [String]?) -> Void)?

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        context.coordinator.parent = self
        nsView.isRecording = isRecording
        nsView.displayTitle = displayString
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var displayString: String {
        if isRecording {
            return "Type shortcut..."
        }
        if let code = keyCode {
            let keyStr = KeyCodeHelper.formattedShortcut(keyCode: code, modifiers: modifiers)
            return "\(keyStr)  [Code: \(code)]"
        }
        return placeholder
    }

    class Coordinator: NSObject, KeyCaptureViewDelegate {
        var parent: ShortcutCaptureButton

        init(parent: ShortcutCaptureButton) {
            self.parent = parent
        }

        func keyCaptureViewDidStartRecording() {
            parent.isRecording = true
        }

        func keyCaptureViewDidCancel() {
            parent.isRecording = false
        }

        func keyCaptureViewDidClear() {
            parent.keyCode = nil
            parent.modifiers = nil
            parent.isRecording = false
            parent.onShortcutChanged?(nil, nil)
        }

        func keyCaptureViewDidCapture(keyCode: UInt16, modifiers: [String]) {
            let mods = modifiers.isEmpty ? nil : modifiers
            parent.keyCode = keyCode
            parent.modifiers = mods
            parent.isRecording = false
            parent.onShortcutChanged?(keyCode, mods)
        }
    }
}

protocol KeyCaptureViewDelegate: AnyObject {
    func keyCaptureViewDidStartRecording()
    func keyCaptureViewDidCancel()
    func keyCaptureViewDidClear()
    func keyCaptureViewDidCapture(keyCode: UInt16, modifiers: [String])
}

final class KeyCaptureView: NSView {
    weak var delegate: KeyCaptureViewDelegate?
    var isRecording: Bool = false
    var displayTitle: String = ""

    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1.2
    }

    override var intrinsicContentSize: NSSize {
        let text = displayTitle as NSString
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let size = text.size(withAttributes: [.font: font])
        return NSSize(width: max(160, size.width + 28), height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isRecording {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = (isDark ? NSColor.controlAccentColor.withAlphaComponent(0.25) : NSColor.controlAccentColor.withAlphaComponent(0.12)).cgColor
        } else {
            layer?.borderColor = (isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.18)).cgColor
            layer?.backgroundColor = (isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)).cgColor
        }

        let font = isRecording ? NSFont.systemFont(ofSize: 12, weight: .semibold) : NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let textColor = isRecording ? NSColor.controlAccentColor : (displayTitle.hasPrefix("Click") ? NSColor.secondaryLabelColor : NSColor.labelColor)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let text = displayTitle as NSString
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: 0,
            y: (bounds.height - textSize.height) / 2,
            width: bounds.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        } else {
            stopRecording(cancelled: true)
        }
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        displayTitle = "Type shortcut..."
        delegate?.keyCaptureViewDidStartRecording()
        needsDisplay = true

        // Engage EventTapManager to intercept and swallow global hotkeys (like Ctrl+Down for App Exposé or Ctrl+Up for Mission Control)
        EventTapManager.shared.startRecordingShortcut(
            onCapture: { [weak self] keyCode, mods in
                DispatchQueue.main.async {
                    self?.delegate?.keyCaptureViewDidCapture(keyCode: keyCode, modifiers: mods)
                    self?.stopRecording(cancelled: false)
                }
            },
            onFlagsChanged: { [weak self] mods in
                DispatchQueue.main.async {
                    if !mods.isEmpty {
                        self?.displayTitle = KeyCodeHelper.formattedModifiersString(mods) + " ..."
                    } else {
                        self?.displayTitle = "Type shortcut..."
                    }
                    self?.needsDisplay = true
                }
            },
            onCancel: { [weak self] in
                DispatchQueue.main.async {
                    self?.stopRecording(cancelled: true)
                }
            },
            onClear: { [weak self] in
                DispatchQueue.main.async {
                    self?.delegate?.keyCaptureViewDidClear()
                    self?.stopRecording(cancelled: false)
                }
            }
        )

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                let currentMods = KeyCodeHelper.modifiersFromNSEventFlags(event.modifierFlags)
                if !currentMods.isEmpty {
                    self.displayTitle = KeyCodeHelper.formattedModifiersString(currentMods) + " ..."
                } else {
                    self.displayTitle = "Type shortcut..."
                }
                self.needsDisplay = true
                return nil
            }

            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape cancels recording
                    self.stopRecording(cancelled: true)
                    return nil
                }

                // Bare Delete / Backspace clears shortcut
                if event.keyCode == 51 && event.modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty {
                    self.delegate?.keyCaptureViewDidClear()
                    self.stopRecording(cancelled: false)
                    return nil
                }

                let mods = KeyCodeHelper.modifiersFromNSEventFlags(event.modifierFlags)
                self.delegate?.keyCaptureViewDidCapture(keyCode: event.keyCode, modifiers: mods)
                self.stopRecording(cancelled: false)
                return nil
            }
            return event
        }
    }

    private func stopRecording(cancelled: Bool) {
        isRecording = false
        EventTapManager.shared.stopRecordingShortcut()
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if cancelled {
            delegate?.keyCaptureViewDidCancel()
        }
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording(cancelled: true)
        }
        return super.resignFirstResponder()
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
