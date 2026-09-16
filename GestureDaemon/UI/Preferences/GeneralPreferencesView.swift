import SwiftUI
import AppKit

public struct GeneralPreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var launchAtLogin: Bool = LoginItemManager.shared.isLaunchAtLoginEnabled
    @State private var showResetConfirmation: Bool = false

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Hardware & Trigger
                triggerSection

                // Section 2: Sensitivity & Physics
                sensitivitySection

                // Section 3: App & System Integration
                systemSection

                // Section 4: Permissions
                permissionsSection

                // Section 5: Advanced & Reset
                advancedSection
            }
            .padding(16)
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
        HStack(spacing: 12) {
            Button("Open config.plist in Editor...") {
                viewModel.openConfigFileInEditor()
            }
            .help("Edit raw XML property list directly")

            Spacer()

            Button("Reset to Factory Defaults...") {
                showResetConfirmation = true
            }
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

