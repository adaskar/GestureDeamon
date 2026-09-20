import SwiftUI
import AppKit

public struct AppProfilesPreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    private var configuredBundleIds: [String] {
        guard let apps = viewModel.config.applications else { return [] }
        return apps.keys.sorted()
    }

    public var body: some View {
        HSplitView {
            // Left sidebar: App list
            VStack(spacing: 0) {
                List(selection: $viewModel.selectedAppBundleId) {
                    ForEach(configuredBundleIds, id: \.self) { bundleId in
                        appRow(bundleId: bundleId)
                            .tag(bundleId)
                    }
                }
                .listStyle(SidebarListStyle())

                Divider()

                // Add / Remove toolbar
                HStack(spacing: 8) {
                    Button(action: promptAddApplication) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Add application from /Applications")

                    Button(action: removeSelectedApplication) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(viewModel.selectedAppBundleId == nil)
                    .help("Remove selected application override")

                    Spacer()
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 200, maxWidth: 260)

            // Right content: Profile detail
            VStack {
                if let selectedBundle = viewModel.selectedAppBundleId,
                   let profile = viewModel.config.applications?[selectedBundle] {
                    appProfileDetailView(bundleId: selectedBundle, profile: profile)
                } else {
                    emptyStateView
                }
            }
            .frame(minWidth: 420)
        }
        .onAppear {
            if viewModel.selectedAppBundleId == nil {
                viewModel.selectedAppBundleId = configuredBundleIds.first
            }
        }
    }

    // MARK: - Subviews

    private func appRow(bundleId: String) -> some View {
        HStack(spacing: 8) {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appURL.deletingPathExtension().lastPathComponent)
                        .font(.body)
                        .lineLimit(1)
                    Text(bundleId)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "app")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bundleId)
                        .font(.body)
                        .lineLimit(1)
                    Text("Custom identifier")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func appProfileDetailView(bundleId: String, profile: AppProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // App Header
                HStack(spacing: 12) {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appURL.deletingPathExtension().lastPathComponent)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(bundleId)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Image(systemName: "app.badge.checkmark")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bundleId)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Prefix-matched Application Identifier")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.bottom, 4)

                // Info Note
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Actions configured below override the global gesture settings whenever this application is frontmost. Slots set to Inherit will use your global gestures.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.08))
                .cornerRadius(8)

                // Smooth Scrolling App Override
                smoothScrollOverrideCard(bundleId: bundleId)

                // Slots Overrides
                VStack(spacing: 12) {
                    slotOverrideCard(slot: .click, title: "Thumb Click", bundleId: bundleId)
                    slotOverrideCard(slot: .dragLeft, title: "Swipe Left", bundleId: bundleId)
                    slotOverrideCard(slot: .dragRight, title: "Swipe Right", bundleId: bundleId)
                    slotOverrideCard(slot: .dragUp, title: "Swipe Up", bundleId: bundleId)
                    slotOverrideCard(slot: .dragDown, title: "Swipe Down", bundleId: bundleId)
                    slotOverrideCard(slot: .scrollUp, title: "Thumb + Scroll Up", bundleId: bundleId)
                    slotOverrideCard(slot: .scrollDown, title: "Thumb + Scroll Down", bundleId: bundleId)
                    slotOverrideCard(slot: .backButton, title: "Back Button", bundleId: bundleId)
                    slotOverrideCard(slot: .forwardButton, title: "Forward Button", bundleId: bundleId)
                }
            }
            .padding(16)
        }
    }

    private func slotOverrideCard(slot: ActionSlot, title: String, bundleId: String) -> some View {
        let currentAction = viewModel.config.applications?[bundleId]?.action(for: slot)
        let isOverridden = currentAction != nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Picker("", selection: Binding(
                    get: { isOverridden ? "override" : "inherit" },
                    set: { mode in
                        if mode == "override" {
                            let fallback = viewModel.config.globalAction(for: slot) ?? ActionDefinition(type: .shortcut, keyCode: 126, modifiers: ["Control"])
                            viewModel.setAppAction(bundleId: bundleId, slot: slot, action: fallback)
                        } else {
                            viewModel.setAppAction(bundleId: bundleId, slot: slot, action: nil)
                        }
                    }
                )) {
                    Text("Inherit Global").tag("inherit")
                    Text("Override").tag("override")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 170)
            }

            if isOverridden {
                ActionEditorView(action: Binding(
                    get: { viewModel.config.applications?[bundleId]?.action(for: slot) },
                    set: { newAct in
                        viewModel.setAppAction(bundleId: bundleId, slot: slot, action: newAct)
                    }
                ))
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Application Selected")
                .font(.headline)

            Text("Select an existing app profile from the sidebar or click '+' to add a new app and customize its gestures.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Add Application...") {
                promptAddApplication()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func smoothScrollOverrideCard(bundleId: String) -> some View {
        let override = viewModel.config.applications?[bundleId]?.smoothScrollEnabled
        let modeBinding = Binding<String>(
            get: {
                if let ov = override {
                    return ov ? "enabled" : "disabled"
                }
                return "inherit"
            },
            set: { newMode in
                guard var apps = viewModel.config.applications, var profile = apps[bundleId] else { return }
                switch newMode {
                case "enabled": profile.smoothScrollEnabled = true
                case "disabled": profile.smoothScrollEnabled = false
                default: profile.smoothScrollEnabled = nil
                }
                apps[bundleId] = profile
                viewModel.config.applications = apps
            }
        )

        return HStack(spacing: 12) {
            Image(systemName: "computermouse.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Smooth Scrolling Override")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Enable or disable smooth scrolling specifically for this application.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("", selection: modeBinding) {
                Text("Inherit Global").tag("inherit")
                Text("Force Enabled").tag("enabled")
                Text("Force Disabled").tag("disabled")
            }
            .frame(width: 140)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private func promptAddApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add Profile"

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                viewModel.addApplicationProfile(bundleId: bundleId)
            }
        }
    }

    private func removeSelectedApplication() {
        guard let bundleId = viewModel.selectedAppBundleId else { return }
        viewModel.removeApplicationProfile(bundleId: bundleId)
    }
}

