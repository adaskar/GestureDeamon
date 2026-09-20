import SwiftUI

public struct SmoothScrollPreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    @State private var testScrollOffset: CGFloat = 0

    private var smoothBinding: Binding<SmoothScrollConfig> {
        Binding(
            get: { viewModel.config.smoothScroll ?? SmoothScrollConfig() },
            set: { viewModel.config.smoothScroll = $0 }
        )
    }

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Master Enable
                masterToggleCard

                if smoothBinding.wrappedValue.enabled {
                    // Section 2: Direction & Inversion
                    directionCard

                    // Section 3: Motion & Physics
                    physicsCard

                    // Section 4: Hotkey Modifiers
                    modifiersCard

                    // Section 5: Live Scroll Test Area
                    liveScrollTesterCard
                }
            }
            .padding(24)
        }
    }

    // MARK: - Master Toggle
    private var masterToggleCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 28))
                .foregroundColor(smoothBinding.wrappedValue.enabled ? .accentColor : .secondary)
                .frame(width: 44, height: 44)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text("Smooth Scrolling Engine")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Transform discrete mouse wheel clicks into fluid, 120Hz display-synced motion with trackpad momentum simulation.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: smoothBinding.enabled)
                .toggleStyle(SwitchToggleStyle())
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Direction Card
    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Scroll Direction", systemImage: "arrow.up.and.down.circle.fill")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Invert mouse wheel scrolling without altering your MacBook trackpad's Natural Scrolling setting.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reverse Vertical Direction")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Scroll up moves view down (traditional mouse behavior independent of trackpad)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: smoothBinding.reverseVertical)
                    .toggleStyle(SwitchToggleStyle())
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reverse Horizontal Direction")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Reverse left-to-right horizontal wheel movement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: smoothBinding.reverseHorizontal)
                    .toggleStyle(SwitchToggleStyle())
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Motion & Physics
    private var physicsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Physics & Interpolation", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Fine-tune the easing curve and momentum characteristics.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simulate Trackpad Momentum")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Generates continuous inertia phases matching native macOS trackpad coasting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: smoothBinding.simulateTrackpad)
                    .toggleStyle(SwitchToggleStyle())
            }

            HStack(spacing: 24) {
                Toggle("Smooth Vertical Axis", isOn: smoothBinding.smoothVertical)
                    .toggleStyle(CheckboxToggleStyle())
                Toggle("Smooth Horizontal Axis", isOn: smoothBinding.smoothHorizontal)
                    .toggleStyle(CheckboxToggleStyle())
            }

            Divider()

            // Speed Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Speed Multiplier")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.2fx", smoothBinding.wrappedValue.speed))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: smoothBinding.speed, in: 1.0...5.0, step: 0.1)
            }

            // Step Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Minimum Step Distance (px)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f px", smoothBinding.wrappedValue.step))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: smoothBinding.step, in: 10.0...80.0, step: 1.0)
            }

            // Duration Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Smoothness / Easing Duration")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.2f", smoothBinding.wrappedValue.duration))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: smoothBinding.duration, in: 1.0...5.0, step: 0.05)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Hotkey Modifiers
    private var modifiersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Modifier Key Shortcuts", systemImage: "command")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Special modifier keys to instantly accelerate, tilt, or bypass smoothing.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Dash
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dash (Speed Boost 5x)")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Hold modifier key to accelerate scrolling 5x through long documents")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { smoothBinding.wrappedValue.dashModifier ?? "Option" },
                    set: { smoothBinding.wrappedValue.dashModifier = $0 }
                )) {
                    Text("Option (⌥)").tag("Option")
                    Text("Shift (⇧)").tag("Shift")
                    Text("Control (⌃)").tag("Control")
                    Text("Command (⌘)").tag("Command")
                    Text("None").tag("None")
                }
                .frame(width: 140)
            }

            // Shift direction
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shift Direction (Vertical → Horizontal)")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Hold modifier key to convert vertical wheel scrolling into horizontal scrolling")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { smoothBinding.wrappedValue.toggleModifier ?? "Shift" },
                    set: { smoothBinding.wrappedValue.toggleModifier = $0 }
                )) {
                    Text("Shift (⇧)").tag("Shift")
                    Text("Option (⌥)").tag("Option")
                    Text("Control (⌃)").tag("Control")
                    Text("Command (⌘)").tag("Command")
                    Text("None").tag("None")
                }
                .frame(width: 140)
            }

            // Block Bypass
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block / Direct Passthrough")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Hold modifier key to bypass smoothing for precision CAD, 3D modeling, or zoom")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { smoothBinding.wrappedValue.blockModifier ?? "Command" },
                    set: { smoothBinding.wrappedValue.blockModifier = $0 }
                )) {
                    Text("Command (⌘)").tag("Command")
                    Text("Option (⌥)").tag("Option")
                    Text("Control (⌃)").tag("Control")
                    Text("Shift (⇧)").tag("Shift")
                    Text("None").tag("None")
                }
                .frame(width: 140)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Live Scroll Tester Area
    private var liveScrollTesterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Scroll Playground", systemImage: "hand.tap.fill")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("Scroll over the box below to test feel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Try scrolling, holding the Dash modifier (5x speed), or holding Shift for horizontal scrolling.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Scrollable canvas inside the preferences pane
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(1...30, id: \.self) { i in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text("\(i)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                )

                            Text("Smooth Scroll Item #\(i) — Notice the 120Hz display refresh sync and fluid inertia")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.primary)

                            Spacer()

                            Text("Row \(i)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(i % 2 == 0 ? Color(NSColor.controlBackgroundColor).opacity(0.6) : Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                        .frame(minWidth: 540)
                    }
                }
                .padding(12)
            }
            .frame(height: 190)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

