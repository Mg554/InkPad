import SwiftUI

/// A live outline built from how the speaker structured the lecture. Tap a
/// line to hear that moment again. Everything is read from the transcript on
/// this iPad.
struct AcousticDiagramSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [DiagramRow]
    let onJump: (TimeInterval) -> Void

    private var groups: [String] {
        var seen: [String] = []
        for row in rows where !seen.contains(row.group) { seen.append(row.group) }
        return seen
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        tr("No structure heard yet"),
                        systemImage: "chart.flow",
                        description: Text(tr("The outline appears as the speaker compares, sequences or groups ideas."))
                    )
                } else {
                    List {
                        ForEach(groups, id: \.self) { group in
                            Section(tr(group)) {
                                ForEach(rows.filter { $0.group == group }) { row in
                                    Button {
                                        onJump(row.time)
                                        dismiss()
                                    } label: {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(AudioClock.string(row.time))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            Text(verbatim: row.text)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("Live Diagram"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}
