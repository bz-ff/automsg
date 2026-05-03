import SwiftUI

struct DraftCardView: View {
    @Binding var draft: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pencil.and.outline")
                    .foregroundColor(.blue)
                Text("AI Draft")
                    .font(.headline)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 12) {
                Button(action: onSend) {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.isEmpty || isGenerating)

                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)

                Spacer()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}
