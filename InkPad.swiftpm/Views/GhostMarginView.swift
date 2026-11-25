import SwiftUI

/// One faded question at the page margin. Tapping it hands the question to
/// Ask This Page; leaving it alone fades it out on its own.
struct GhostMarginView: View {
    let question: GhostQuestion
    let onPromote: () -> Void
    let onDismiss: () -> Void

    @State private var faded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "questionmark.bubble")
                    .foregroundStyle(Color.inkAccent)
                Button {
                    onPromote()
                    onDismiss()
                } label: {
                    Text(verbatim: question.text)
                        .font(.footnote.italic())
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.inkAccent.opacity(0.25), lineWidth: 1)
            )
            HStack {
                Spacer()
                Button(tr("Dismiss")) { onDismiss() }
                    .font(.caption2)
                    .buttonStyle(.borderless)
            }
        }
        .frame(width: 230)
        .opacity(faded ? 0.18 : 0.72)
        .onAppear {
            withAnimation(.easeOut(duration: 2)) { faded = true }
        }
        .accessibilityLabel(tr("Socratic Ghost"))
    }
}
