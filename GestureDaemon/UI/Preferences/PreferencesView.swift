import SwiftUI

public struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @State private var selectedTab: PreferencesTab = .gestures

    public enum PreferencesTab: String, CaseIterable, Identifiable {
        case gestures = "Gestures"
        case sideButtons = "Side Buttons"
        case appProfiles = "App Profiles"
        case general = "General & Tuning"
        case liveTester = "Live Tester"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .gestures: return "hand.draw.fill"
            case .sideButtons: return "arrow.left.and.right.circle.fill"
            case .appProfiles: return "app.badge.fill"
            case .general: return "gearshape.fill"
            case .liveTester: return "gauge.with.needle.fill"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Segmented Tab Switcher
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(PreferencesTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(maxWidth: 580)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // Active Tab Content
            Group {
                switch selectedTab {
                case .gestures:
                    GesturesPreferencesView(viewModel: viewModel)
                case .sideButtons:
                    SideButtonsPreferencesView(viewModel: viewModel)
                case .appProfiles:
                    AppProfilesPreferencesView(viewModel: viewModel)
                case .general:
                    GeneralPreferencesView(viewModel: viewModel)
                case .liveTester:
                    LiveTesterView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedTab) { newTab in
            if newTab != .liveTester {
                EventTapManager.shared.isCalibrationMode = false
                EventTapManager.shared.resetState()
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("GestureDaemon")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1")")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.quaternaryLabelColor))
                        .cornerRadius(4)

                    if let devName = HIDPlusPlusManager.shared.connectedDeviceName {
                        Text(devName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                }

                Text("Ultra-low latency mouse gestures & hardware diversion")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Open Config File
            Button(action: {
                viewModel.openConfigFileInEditor()
            }) {
                Label("Open Config", systemImage: "doc.text")
                    .font(.caption)
            }
            .help("Open ~/.config/GestureDaemon/config.plist in default editor")

            // Live Save Status Notification
            if let status = viewModel.saveStatusMessage {
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

