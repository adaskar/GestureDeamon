import SwiftUI
import AppKit

public struct ActionEditorView: View {
    @Binding var action: ActionDefinition?
    var title: String?
    var subtitle: String?

    @State private var currentCategory: ActionCategory

    public enum ActionCategory: String, CaseIterable, Identifiable {
        case preset = "Preset Action"
        case shortcut = "Custom Shortcut"
        case application = "Launch Application"
        case command = "Run Shell Command"
        case none = "None (Disabled)"

        public var id: String { rawValue }
    }

    public init(action: Binding<ActionDefinition?>, title: String? = nil, subtitle: String? = nil) {
        self._action = action
        self.title = title
        self.subtitle = subtitle
        self._currentCategory = State(initialValue: Self.determineCategory(for: action.wrappedValue))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Category Picker
            HStack {
                Picker("Action Type:", selection: $currentCategory) {
                    ForEach(ActionCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 220)
                .onChange(of: currentCategory) { newCat in
                    applyCategoryChange(to: newCat)
                }

                Spacer()
            }

            // Detail Configuration for selected Category
            VStack(alignment: .leading, spacing: 8) {
                switch currentCategory {
                case .preset:
                    presetEditorView
                case .shortcut:
                    shortcutEditorView
                case .application:
                    applicationEditorView
                case .command:
                    commandEditorView
                case .none:
                    HStack {
                        Image(systemName: "slash.circle")
                            .foregroundColor(.secondary)
                        Text("No action will be triggered for this gesture.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
            )
        }
        .onChange(of: action) { newAction in
            syncCategoryWithAction(newAction)
        }
    }

    // MARK: - Subviews

    private var presetEditorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Select Preset:", selection: Binding(
                get: { currentPresetName() },
                set: { newPresetName in
                    if let found = KeyCodeHelper.PresetAction.presets.first(where: { $0.name == newPresetName }) {
                        action = found.action
                    }
                }
            )) {
                ForEach(KeyCodeHelper.PresetAction.presets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            .pickerStyle(MenuPickerStyle())

            if let currentPreset = KeyCodeHelper.PresetAction.presets.first(where: { $0.name == currentPresetName() }) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                    Text(currentPreset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let code = currentPreset.action.keyCode {
                        Text("Key Code: \(code)")
                            .font(.caption2)
                            .monospaced()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            HStack {
                Spacer()
                Button(action: {
                    currentCategory = .shortcut
                }) {
                    Label("Customize as Custom Shortcut...", systemImage: "slider.horizontal.2.square")
                        .font(.caption)
                }
                .buttonStyle(LinkButtonStyle())
            }
        }
    }

    private var shortcutEditorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Shortcut:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ShortcutRecorderView(
                    keyCode: Binding(
                        get: { action?.keyCode },
                        set: { _ in }
                    ),
                    modifiers: Binding(
                        get: { action?.modifiers },
                        set: { _ in }
                    ),
                    placeholder: "Click to Record Shortcut",
                    onShortcutChanged: { newCode, newMods in
                        if let newCode = newCode {
                            let desc = KeyCodeHelper.formattedShortcut(keyCode: newCode, modifiers: newMods)
                            action = ActionDefinition(
                                type: .shortcut,
                                keyCode: newCode,
                                modifiers: newMods,
                                bundleIdentifier: nil,
                                commandPath: nil,
                                comment: "Custom Shortcut (\(desc))"
                            )
                        } else {
                            action = ActionDefinition(
                                type: .shortcut,
                                keyCode: nil,
                                modifiers: nil,
                                bundleIdentifier: nil,
                                commandPath: nil,
                                comment: "Custom Shortcut"
                            )
                        }
                    }
                )

                Spacer()

                Button(action: {
                    currentCategory = .preset
                }) {
                    Text("Choose from Presets...")
                        .font(.caption)
                }
                .buttonStyle(LinkButtonStyle())
            }

            if let code = action?.keyCode {
                HStack {
                    Text("Resolved Key: \(KeyCodeHelper.keyDescriptiveName(for: code))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Virtual Key Code: \(code)")
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Click the box above and press any key combination (e.g. ⌘⇧K, ⌃⌥Space, or F5). Press Esc to cancel, Backspace to clear.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var applicationEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let bundleId = action?.bundleIdentifier,
                   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appURL.deletingPathExtension().lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.secondary)

                    Text(action?.bundleIdentifier ?? "No application selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Choose Application...") {
                    chooseApplication()
                }
            }
        }
    }

    private var commandEditorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shell Command:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("e.g. open -a Notes", text: Binding(
                get: { action?.commandPath ?? "" },
                set: { newCmd in
                    action = ActionDefinition(
                        type: .command,
                        keyCode: nil,
                        modifiers: nil,
                        bundleIdentifier: nil,
                        commandPath: newCmd.isEmpty ? nil : newCmd,
                        comment: "Command: \(newCmd)"
                    )
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.system(.body, design: .monospaced))

            Text("Executed seamlessly in background using /bin/zsh -c")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Category Logic

    private static func determineCategory(for action: ActionDefinition?) -> ActionCategory {
        guard let action = action else { return .none }
        switch action.type {
        case .application:
            return .application
        case .command:
            return .command
        case .shortcut:
            if let comment = action.comment, comment.contains("Custom") {
                return .shortcut
            }
            if KeyCodeHelper.PresetAction.presets.contains(where: {
                $0.action.keyCode == action.keyCode && ($0.action.modifiers ?? []) == (action.modifiers ?? [])
            }) {
                return .preset
            }
            return .shortcut
        }
    }

    private func syncCategoryWithAction(_ newAction: ActionDefinition?) {
        guard let newAction = newAction else {
            if currentCategory != .none { currentCategory = .none }
            return
        }
        let inferred = Self.determineCategory(for: newAction)
        if (currentCategory == .preset || currentCategory == .shortcut) && (inferred == .preset || inferred == .shortcut) {
            // Keep the user's selected mode (preset vs custom shortcut)
            return
        }
        if currentCategory != inferred {
            currentCategory = inferred
        }
    }

    private func currentPresetName() -> String {
        guard let action = action, action.type == .shortcut else {
            return KeyCodeHelper.PresetAction.presets.first?.name ?? ""
        }
        for preset in KeyCodeHelper.PresetAction.presets {
            if preset.action.keyCode == action.keyCode && (preset.action.modifiers ?? []) == (action.modifiers ?? []) {
                return preset.name
            }
        }
        return KeyCodeHelper.PresetAction.presets.first?.name ?? ""
    }

    private func applyCategoryChange(to category: ActionCategory) {
        switch category {
        case .preset:
            if let first = KeyCodeHelper.PresetAction.presets.first {
                action = first.action
            }
        case .shortcut:
            if action?.type == .shortcut {
                let code = action?.keyCode
                let mods = action?.modifiers
                let desc = KeyCodeHelper.formattedShortcut(keyCode: code, modifiers: mods)
                action = ActionDefinition(
                    type: .shortcut,
                    keyCode: code,
                    modifiers: mods,
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Custom Shortcut (\(desc))"
                )
            } else {
                action = ActionDefinition(
                    type: .shortcut,
                    keyCode: nil,
                    modifiers: nil,
                    bundleIdentifier: nil,
                    commandPath: nil,
                    comment: "Custom Shortcut"
                )
            }
        case .application:
            if action?.type != .application {
                action = ActionDefinition(type: .application, bundleIdentifier: "com.apple.Finder", comment: "Finder")
            }
        case .command:
            if action?.type != .command {
                action = ActionDefinition(type: .command, commandPath: "echo 'Gesture triggered'", comment: "Shell Command")
            }
        case .none:
            action = nil
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                let name = url.deletingPathExtension().lastPathComponent
                action = ActionDefinition(
                    type: .application,
                    bundleIdentifier: bundleId,
                    comment: "Launch \(name)"
                )
            }
        }
    }
}
