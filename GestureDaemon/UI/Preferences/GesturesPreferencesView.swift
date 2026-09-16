import SwiftUI

public struct GesturesPreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Info Banner
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.draw.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thumb Button & Directional Gestures")
                            .font(.headline)
                        Text("Hold down the Thumb button on your mouse and swipe in any direction. Releasing or crossing the threshold triggers your chosen action instantly. A quick click without dragging triggers the Click action.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(10)

                // Gesture Cards
                VStack(spacing: 14) {
                    gestureCard(
                        title: "Thumb Click",
                        subtitle: "Quick press and release of the thumb button without dragging the mouse.",
                        icon: "hand.tap.fill",
                        iconColor: .blue,
                        action: $viewModel.config.clickAction
                    )

                    gestureCard(
                        title: "Swipe Left",
                        subtitle: "Hold thumb button and move mouse left beyond threshold distance.",
                        icon: "arrow.left.circle.fill",
                        iconColor: .purple,
                        action: $viewModel.config.dragLeftAction
                    )

                    gestureCard(
                        title: "Swipe Right",
                        subtitle: "Hold thumb button and move mouse right beyond threshold distance.",
                        icon: "arrow.right.circle.fill",
                        iconColor: .purple,
                        action: $viewModel.config.dragRightAction
                    )

                    gestureCard(
                        title: "Swipe Up",
                        subtitle: "Hold thumb button and move mouse up beyond threshold distance.",
                        icon: "arrow.up.circle.fill",
                        iconColor: .orange,
                        action: $viewModel.config.dragUpAction
                    )

                    gestureCard(
                        title: "Swipe Down",
                        subtitle: "Hold thumb button and move mouse down beyond threshold distance.",
                        icon: "arrow.down.circle.fill",
                        iconColor: .orange,
                        action: $viewModel.config.dragDownAction
                    )
                }
            }
            .padding(16)
        }
    }

    private func gestureCard(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        action: Binding<ActionDefinition?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
            }

            ActionEditorView(action: action)
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

