import SwiftUI
import AppKit

public struct LiveTesterView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    @State private var pressedButtons: Set<Int> = []
    @State private var isTriggerDown: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var detectedDirection: String? = nil
    @State private var lastFiredActionDescription: String? = nil
    @State private var localEventMonitor: Any?

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    private var triggerIndex: Int {
        Int(viewModel.config.triggerButtonIndex)
    }

    private var thresholdDistance: CGFloat {
        CGFloat(viewModel.config.thresholdDistance)
    }

    private var deadzoneRadius: CGFloat {
        CGFloat(viewModel.config.deadzoneRadius)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Hardware Status Banner
            HStack {
                Image(systemName: "computermouse")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(HIDPlusPlusManager.shared.connectedDeviceName ?? "Logitech Hardware")
                        .font(.headline)
                    Text(HIDPlusPlusManager.shared.connectedTransport != nil ?
                         "Connected via \(HIDPlusPlusManager.shared.connectedTransport!.rawValue) transport" :
                         "Passive event tap monitoring active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Live Calibration")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(6)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
            )

            // Button Indicators Row
            HStack(spacing: 10) {
                buttonBadge(name: "Left Click", index: 0)
                buttonBadge(name: "Right Click", index: 1)
                buttonBadge(name: "Middle (2)", index: 2)
                buttonBadge(name: "Back (3)", index: 3)
                buttonBadge(name: "Forward (4)", index: 4)
                buttonBadge(name: "Thumb (\(triggerIndex))", index: triggerIndex, isTrigger: true)
            }

            // Radar Visualizer Area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )

                radarCanvas
                    .frame(height: 240)

                VStack {
                    Spacer()
                    radarStatusOverlay
                        .padding(.bottom, 12)
                }
            }
            .frame(height: 240)

            // Explanatory footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Press and hold mouse buttons to test button detection. Hold the Thumb button (Button \(triggerIndex)) and drag to test deadzone, threshold distance, and direction triggers live.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .onAppear {
            startEventMonitoring()
        }
        .onDisappear {
            stopEventMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesWindowController.windowFocusDidChangeNotification)) { _ in
            if PreferencesWindowController.shared.isPreferencesWindowKey {
                startEventMonitoring()
            } else {
                stopEventMonitoring()
            }
        }
    }

    // MARK: - Subviews

    private func buttonBadge(name: String, index: Int, isTrigger: Bool = false) -> some View {
        let isDown = pressedButtons.contains(index)
        return HStack(spacing: 4) {
            Circle()
                .fill(isDown ? (isTrigger ? Color.purple : Color.green) : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(name)
                .font(.caption)
                .fontWeight(isDown ? .bold : .regular)
                .foregroundColor(isDown ? (isTrigger ? .purple : .green) : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isDown ? (isTrigger ? Color.purple.opacity(0.12) : Color.green.opacity(0.12)) : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDown ? (isTrigger ? Color.purple : Color.green) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var radarCanvas: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let scale: CGFloat = 1.6 // visual amplification for responsiveness

            ZStack {
                // Crosshairs
                Path { p in
                    p.move(to: CGPoint(x: 0, y: center.y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: 0))
                    p.addLine(to: CGPoint(x: center.x, y: geo.size.height))
                }
                .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Direction highlights
                directionLabels(center: center)

                // Threshold Circle
                Circle()
                    .stroke(detectedDirection != nil ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: thresholdDistance * 2 * scale, height: thresholdDistance * 2 * scale)
                    .position(center)

                // Deadzone Circle
                Circle()
                    .stroke(Color.orange.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: deadzoneRadius * 2 * scale, height: deadzoneRadius * 2 * scale)
                    .position(center)

                // Dynamic Position Dot
                if isTriggerDown {
                    let clampedX = center.x + (dragOffset.width * scale)
                    let clampedY = center.y + (dragOffset.height * scale)

                    // Connecting Line
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: CGPoint(x: clampedX, y: clampedY))
                    }
                    .stroke(detectedDirection != nil ? Color.accentColor : Color.purple, lineWidth: 2)

                    // Dot
                    Circle()
                        .fill(detectedDirection != nil ? Color.accentColor : Color.purple)
                        .frame(width: 14, height: 14)
                        .shadow(color: (detectedDirection != nil ? Color.accentColor : Color.purple).opacity(0.6), radius: 4)
                        .position(x: clampedX, y: clampedY)
                } else {
                    // Center Idle Marker
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .position(center)
                }
            }
        }
    }

    private func directionLabels(center: CGPoint) -> some View {
        ZStack {
            Text("UP")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(detectedDirection == "UP" ? .accentColor : .secondary.opacity(0.4))
                .position(x: center.x, y: center.y - 85)

            Text("DOWN")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(detectedDirection == "DOWN" ? .accentColor : .secondary.opacity(0.4))
                .position(x: center.x, y: center.y + 85)

            Text("LEFT")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(detectedDirection == "LEFT" ? .accentColor : .secondary.opacity(0.4))
                .position(x: center.x - 110, y: center.y)

            Text("RIGHT")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(detectedDirection == "RIGHT" ? .accentColor : .secondary.opacity(0.4))
                .position(x: center.x + 110, y: center.y)
        }
    }

    private var radarStatusOverlay: some View {
        HStack(spacing: 8) {
            if isTriggerDown {
                let dist = hypot(dragOffset.width, dragOffset.height)
                if dist < deadzoneRadius {
                    Image(systemName: "circle.dotted")
                        .foregroundColor(.orange)
                    Text("Inside Deadzone (\(Int(dist))px / \(Int(deadzoneRadius))px)")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if dist < thresholdDistance {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .foregroundColor(.purple)
                    Text("Swiping... (\(Int(dist))px / \(Int(thresholdDistance))px)")
                        .font(.caption)
                        .foregroundColor(.purple)
                } else if let dir = detectedDirection {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Triggered: Swipe \(dir)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            } else if let last = lastFiredActionDescription {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.accentColor)
                Text(last)
                    .font(.caption)
                    .foregroundColor(.primary)
            } else {
                Text("Hold Trigger Button (Button \(triggerIndex)) & Swipe")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(6)
    }

    // MARK: - Event Monitoring

    private func startEventMonitoring() {
        guard PreferencesWindowController.shared.isPreferencesWindowKey else {
            stopEventMonitoring()
            return
        }

        EventTapManager.shared.isCalibrationMode = true
        EventTapManager.shared.onCalibrationEvent = { [self] event in
            DispatchQueue.main.async {
                handleCalibrationEvent(event)
            }
        }

        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .leftMouseUp,
                .rightMouseDown, .rightMouseUp
            ]) { [self] event in
                switch event.type {
                case .leftMouseDown:
                    pressedButtons.insert(0)
                case .leftMouseUp:
                    pressedButtons.remove(0)
                case .rightMouseDown:
                    pressedButtons.insert(1)
                case .rightMouseUp:
                    pressedButtons.remove(1)
                default:
                    break
                }
                return event
            }
        }
    }

    private func stopEventMonitoring() {
        EventTapManager.shared.isCalibrationMode = false
        EventTapManager.shared.onCalibrationEvent = nil
        EventTapManager.shared.resetState()
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        pressedButtons.removeAll()
        isTriggerDown = false
        dragOffset = .zero
        detectedDirection = nil
    }

    private func handleCalibrationEvent(_ event: CalibrationEvent) {
        switch event {
        case .triggerState(let isDown, let buttonIndex):
            if isDown {
                pressedButtons.insert(buttonIndex)
                isTriggerDown = true
                dragOffset = .zero
                detectedDirection = nil
            } else {
                pressedButtons.remove(buttonIndex)
                isTriggerDown = false
            }

        case .motionUpdated(let dx, let dy, _):
            dragOffset = CGSize(width: dx, height: dy)

        case .directionDetected(let direction, let action):
            if let direction = direction {
                let dirStr: String
                switch direction {
                case .left: dirStr = "LEFT"
                case .right: dirStr = "RIGHT"
                case .up: dirStr = "UP"
                case .down: dirStr = "DOWN"
                }
                detectedDirection = dirStr
                let actionDesc = action?.comment ?? "Swipe \(dirStr)"
                lastFiredActionDescription = "Detected: Swipe \(dirStr) (\(actionDesc))"
            } else {
                detectedDirection = nil
            }

        case .gestureCompleted(let wasClick, let action):
            if wasClick {
                let actionDesc = action?.comment ?? "Thumb Click"
                lastFiredActionDescription = "Detected: Thumb Click (\(actionDesc))"
            } else if let dir = detectedDirection {
                let actionDesc = action?.comment ?? "Swipe \(dir)"
                lastFiredActionDescription = "Detected: Swipe \(dir) (\(actionDesc))"
            }

        case .otherButton(let buttonIndex, let isDown, let actionName):
            if isDown {
                pressedButtons.insert(buttonIndex)
                if let name = actionName {
                    lastFiredActionDescription = "Clicked: Button \(buttonIndex) (\(name))"
                }
            } else {
                pressedButtons.remove(buttonIndex)
            }
        }
    }
}

