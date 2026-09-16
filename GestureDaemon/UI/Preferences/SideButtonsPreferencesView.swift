import SwiftUI

public struct SideButtonsPreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Side Navigation Buttons", isOn: Binding(
                        get: { viewModel.config.enableSideButtons ?? true },
                        set: { viewModel.config.enableSideButtons = $0 }
                    ))
                    .font(.headline)

                    Text("When enabled, GestureDaemon intercepts hardware side buttons (typically Button 3 and 4) and handles them cleanly with zero latency, overriding noisy default OS mouse clicks.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                )

                if viewModel.config.enableSideButtons ?? true {
                    // Back Button Card
                    buttonConfigCard(
                        title: "Back Button",
                        subtitle: "Side button closest to the thumb rest. Defaults to Universal Navigation Back (⌘[).",
                        icon: "arrow.backward.circle.fill",
                        iconColor: .teal,
                        buttonIndex: Binding(
                            get: { Int(viewModel.config.backButtonIndex ?? 3) },
                            set: { viewModel.config.backButtonIndex = Int64($0) }
                        ),
                        action: $viewModel.config.backButtonAction
                    )

                    // Forward Button Card
                    buttonConfigCard(
                        title: "Forward Button",
                        subtitle: "Frontmost side button. Defaults to Universal Navigation Forward (⌘]).",
                        icon: "arrow.forward.circle.fill",
                        iconColor: .teal,
                        buttonIndex: Binding(
                            get: { Int(viewModel.config.forwardButtonIndex ?? 4) },
                            set: { viewModel.config.forwardButtonIndex = Int64($0) }
                        ),
                        action: $viewModel.config.forwardButtonAction
                    )
                }
            }
            .padding(16)
        }
    }

    private func buttonConfigCard(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        buttonIndex: Binding<Int>,
        action: Binding<ActionDefinition?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Hardware Button:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: buttonIndex) {
                        Text("Button 3 (Default Back)").tag(3)
                        Text("Button 4 (Default Forward)").tag(4)
                        Text("Button 5").tag(5)
                        Text("Button 2 (Middle)").tag(2)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 170)
                }
            }

            ActionEditorView(
                action: action,
                subtitle: action.wrappedValue == nil ? "Default macOS universal navigation will be used" : nil
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

