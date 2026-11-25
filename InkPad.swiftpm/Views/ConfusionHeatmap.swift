import SwiftUI

/// Opt-in luxury tier: a thermal overlay over the spots where writing
/// slowed down or was rewritten. The map is read from ink already on this
/// iPad; nothing is sent anywhere unless the owner asks the AI.
struct ConfusionHeatmap: View {
    let report: FrictionReport
    let page: Int
    let audio: AudioController
    @Binding var selected: FrictionPoint?

    var body: some View {
        GeometryReader { geometry in
            ForEach(visible) { point in
                let spot = spotPosition(point, in: geometry.size)
                Button {
                    selected = point
                    audio.play(from: point.date)
                } label: {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.55), Color.red.opacity(0.12), Color.clear],
                                center: .center, startRadius: 2, endRadius: 34
                            )
                        )
                        .frame(width: 68, height: 68)
                        .overlay(
                            Circle().stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .position(spot)
                .accessibilityLabel(point.title)
                .accessibilityHint(point.detail)
            }
        }
        .allowsHitTesting(!visible.isEmpty)
    }

    private var visible: [FrictionPoint] {
        report.points.filter { $0.page == page && $0.hasLocation }
    }

    private func spotPosition(_ point: FrictionPoint, in size: CGSize) -> CGPoint {
        let x = min(max(point.x ?? 0, 0.04), 0.96)
        let y = min(max(point.y ?? 0, 0.04), 0.96)
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}

/// What a tap on a heat spot opens: what was noticed, the moment on the
/// recording, and a button that asks the configured AI (Firewall rules still
/// apply) for a breakdown.
struct ConfusionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let point: FrictionPoint
    let noteID: UUID
    let onAsk: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Label(tr("Hard moment"), systemImage: "waveform.path.ecg")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.inkAccent)
                Text(verbatim: point.title)
                    .font(.headline)
                Text(verbatim: point.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(trMessage("On page {}. Tap the spot again while a recording is open to hear this moment.")
                    .replacingOccurrences(of: "{}", with: String(point.page + 1)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onAsk()
                    dismiss()
                } label: {
                    Label(tr("Ask AI About This"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.inkAccent)
            }
            .padding()
            .navigationTitle(tr("Cognitive Replay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}
