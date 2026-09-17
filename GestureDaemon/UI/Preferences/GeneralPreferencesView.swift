import SwiftUI
import AppKit

public struct GeneralPreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var launchAtLogin: Bool = LoginItemManager.shared.isLaunchAtLoginEnabled
    @State private var showResetConfirmation: Bool = false
    @State private var batteryInfo: HIDPlusPlusManager.BatteryInfo? = HIDPlusPlusManager.shared.batteryInfo
    @State private var connectedDeviceName: String? = HIDPlusPlusManager.shared.connectedDeviceName
    @State private var connectedTransport: HIDPlusPlusManager.TransportType? = HIDPlusPlusManager.shared.connectedTransport
    @State private var currentDpi: Int? = HIDPlusPlusManager.shared.currentDpi
    @State private var isSmartShiftSupported: Bool = HIDPlusPlusManager.shared.isSmartShiftSupported
    @State private var isDpiSupported: Bool = HIDPlusPlusManager.shared.isDpiSupported

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Hardware Controls (HID++)
                hardwareSection

                // Section 2: Hardware & Trigger
                triggerSection

                // Section 3: Sensitivity & Physics
                sensitivitySection

                // Section 4: App & System Integration
                systemSection

                // Section 5: Permissions
                permissionsSection

                // Section 6: Advanced & Reset
                advancedSection
            }
            .padding(16)
        }
        .onAppear {
            HIDPlusPlusManager.shared.refreshBatteryStatus()
            HIDPlusPlusManager.shared.queryCurrentDpi()
            self.isSmartShiftSupported = HIDPlusPlusManager.shared.isSmartShiftSupported
            self.isDpiSupported = HIDPlusPlusManager.shared.isDpiSupported
        }
        .onReceive(NotificationCenter.default.publisher(for: .hidBatteryStatusDidChange)) { notif in
            self.batteryInfo = notif.object as? HIDPlusPlusManager.BatteryInfo ?? HIDPlusPlusManager.shared.batteryInfo
        }
        .onReceive(NotificationCenter.default.publisher(for: .hidHardwareCapabilitiesDidChange)) { _ in
            self.connectedDeviceName = HIDPlusPlusManager.shared.connectedDeviceName
            self.connectedTransport = HIDPlusPlusManager.shared.connectedTransport
            self.batteryInfo = HIDPlusPlusManager.shared.batteryInfo
            self.currentDpi = HIDPlusPlusManager.shared.currentDpi
            self.isSmartShiftSupported = HIDPlusPlusManager.shared.isSmartShiftSupported
            self.isDpiSupported = HIDPlusPlusManager.shared.isDpiSupported
        }
        .onReceive(NotificationCenter.default.publisher(for: .hidDpiDidChange)) { notif in
            if let dpi = notif.object as? Int {
                self.currentDpi = dpi
            }
        }
        .alert(isPresented: $showResetConfirmation) {
            Alert(
                title: Text("Reset to Factory Defaults?"),
                message: Text("All gesture mappings, sensitivity tuning, and application profiles will be restored to their original default settings."),
                primaryButton: .destructive(Text("Reset to Defaults")) {
                    viewModel.resetToDefaults()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sections

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hardware Controls (HID++)", systemImage: "cpu")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Device & Battery Status Row
                HStack(spacing: 12) {
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectedDeviceName ?? "Logitech Device")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack(spacing: 6) {
                            Image(systemName: connectedTransport == .bluetoothLE ? "antenna.radiowaves.left.and.right" : "cable.connector")
                                .font(.caption2)
                            Text(connectedTransport?.rawValue ?? "Searching...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if let battery = batteryInfo {
                        HStack(spacing: 6) {
                            Image(systemName: batteryIconName(for: battery))
                                .foregroundColor(battery.percentage <= 20 && !battery.isCharging ? .red : .primary)
                            Text("\(battery.percentage)%")
                                .font(.subheadline)
                                .monospacedDigit()
                            if battery.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }

                // SmartShift Flywheel Control (only shown if hardware supports electronic flywheel clutch)
                if isSmartShiftSupported {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("SmartShift", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { viewModel.config.smartShiftEnabled ?? true },
                                set: { enabled in
                                    viewModel.config.smartShiftEnabled = enabled
                                    let threshold = viewModel.config.smartShiftThreshold ?? 20
                                    HIDPlusPlusManager.shared.setSmartShift(enabled: enabled, threshold: threshold)
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                        }

                        if viewModel.config.smartShiftEnabled ?? true {
                            HStack(spacing: 12) {
                                Image(systemName: "gauge.low")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.config.smartShiftThreshold ?? 20) },
                                        set: { val in
                                            let intVal = Int(val)
                                            viewModel.config.smartShiftThreshold = intVal
                                            HIDPlusPlusManager.shared.setSmartShift(enabled: true, threshold: intVal)
                                        }
                                    ),
                                    in: 1...50,
                                    step: 1
                                )

                                Image(systemName: "gauge.high")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(viewModel.config.smartShiftThreshold ?? 20)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }

                // Sensor DPI Control (only shown if hardware supports software adjustable DPI)
                if isDpiSupported {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Sensor DPI", systemImage: "scope")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            Text("\(viewModel.config.sensorDpi ?? (currentDpi ?? 1000)) DPI")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "tortoise.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.config.sensorDpi ?? (currentDpi ?? 1000)) },
                                    set: { val in
                                        let dpiVal = Int(val)
                                        viewModel.config.sensorDpi = dpiVal
                                        HIDPlusPlusManager.shared.setSensorDpi(dpi: dpiVal)
                                    }
                                ),
                                in: 200...4000,
                                step: 50
                            )

                            Image(systemName: "hare.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Device Capabilities Summary (when advanced motorized controls are not supported on this model)
                if !isSmartShiftSupported && !isDpiSupported && connectedDeviceName != nil {
                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("SmartShift & software DPI are not available on \(connectedDeviceName ?? "this device").")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }

    private func batteryIconName(for info: HIDPlusPlusManager.BatteryInfo) -> String {
        if info.isCharging { return "battery.100.bolt" }
        switch info.percentage {
        case 85...100: return "battery.100"
        case 60..<85:  return "battery.75"
        case 35..<60:  return "battery.50"
        case 15..<35:  return "battery.25"
        default:       return "battery.0"
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trigger Button & Click Behavior", systemImage: "computermouse.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Trigger Button:")
                        .frame(width: 140, alignment: .leading)

                    Picker("", selection: $viewModel.config.triggerButtonIndex) {
                        Text("Button 5 (Thumb / Gesture Button)").tag(Int64(5))
                        Text("Button 4 (Side Forward)").tag(Int64(4))
                        Text("Button 3 (Side Back)").tag(Int64(3))
                        Text("Button 2 (Middle Click)").tag(Int64(2))
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 260)

                    Spacer()
                }

                Text("Holding this button down activates directional mouse swiping. On Logitech MX Master series, Button 5 is the thumb gesture button.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 2)

                Toggle("Swallow Raw Trigger Events", isOn: $viewModel.config.swallowTriggerEvents)
                    .font(.subheadline)

                Text("Suppresses raw mouse click events from reaching underlying desktop windows when pressing the trigger button, preventing accidental clicks while swiping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gesture Sensitivity & Tuning", systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                // Threshold Distance
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Threshold Distance:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(viewModel.config.thresholdDistance)) px")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    Slider(
                        value: $viewModel.config.thresholdDistance,
                        in: 10...100,
                        step: 1
                    )

                    Text("Distance in screen pixels you must move the mouse while holding the trigger button to confirm a swipe. Lower = fast flicks; Higher = deliberate drags. (Default: 35 px)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Deadzone Radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Deadzone Radius:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(viewModel.config.deadzoneRadius)) px")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    Slider(
                        value: $viewModel.config.deadzoneRadius,
                        in: 0...30,
                        step: 1
                    )

                    Text("Ignores small hand jitters when pressing the thumb button so clicking doesn't accidentally trigger a swipe. (Default: 8 px)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Gesture Window
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Gesture Window:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(viewModel.config.gestureWindowMs ?? 75.0)) ms")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.config.gestureWindowMs ?? 75.0 },
                            set: { viewModel.config.gestureWindowMs = $0 }
                        ),
                        in: 20...200,
                        step: 5
                    )

                    Text("Initial grace period in milliseconds after button press before evaluating drag direction. (Default: 75 ms)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("System & Menu Bar", systemImage: "macwindow")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Show Menu Bar Icon
                Toggle("Show GestureDaemon in Menu Bar", isOn: Binding(
                    get: { viewModel.config.showMenuBarIcon ?? true },
                    set: { show in
                        viewModel.config.showMenuBarIcon = show
                        ConfigManager.shared.updateShowMenuBarIcon(show)
                    }
                ))
                .font(.subheadline)

                Text("Keep GestureDaemon accessible from the top menu bar. When disabled, re-launch GestureDaemon from Applications or Spotlight to reveal settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Launch at Login
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchAtLogin = LoginItemManager.shared.setLaunchAtLogin(enabled: enabled)
                    }
                ))
                .font(.subheadline)

                Text("Automatically start GestureDaemon silently in the background when you log in to macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Logging
                HStack {
                    Toggle("Enable Diagnostic Logging", isOn: Binding(
                        get: { viewModel.config.enableLogging ?? false },
                        set: { viewModel.config.enableLogging = $0 }
                    ))
                    .font(.subheadline)

                    Spacer()

                    if viewModel.config.enableLogging ?? false {
                        Picker("Log Level:", selection: Binding(
                            get: { viewModel.config.logLevel ?? "Info" },
                            set: { viewModel.config.logLevel = $0 }
                        )) {
                            Text("Debug").tag("Debug")
                            Text("Info").tag("Info")
                            Text("Warn").tag("Warn")
                            Text("Error").tag("Error")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 140)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("macOS System Permissions", systemImage: "lock.shield.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    name: "Accessibility",
                    description: "Required for global event taps and dispatching synthetic keyboard shortcuts.",
                    granted: PermissionHelper.isAccessibilityGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )

                Divider()

                permissionRow(
                    name: "Input Monitoring",
                    description: "Required for Bluetooth Low Energy (BLE) direct HID++ report pipe reading without USB dongles.",
                    granted: PermissionHelper.isInputMonitoringGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                )
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }

    private func permissionRow(name: String, description: String, granted: Bool, settingsURL: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(granted ? "Granted" : "Missing Authorization")
                        .font(.caption)
                        .foregroundColor(granted ? .green : .orange)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !granted {
                Button("Authorize...") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Configuration File & Factory Reset", systemImage: "doc.badge.gearshape")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Configuration File")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Edit your custom property list directly (~/.config/GestureDaemon/config.plist).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Open in Editor...") {
                        viewModel.openConfigFileInEditor()
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset to Defaults")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Restore all gesture bindings and settings to factory defaults.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Reset to Defaults...") {
                        showResetConfirmation = true
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }
}

