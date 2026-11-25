import SwiftUI

/// Native approximation of an executable canvas: formulas written in the
/// note are worked out on the iPad and shown beside the ink. No browser,
/// WebGL or network is involved.
struct LiveMathSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [MathLine]

    var body: some View {
        NavigationStack {
            Group {
                if lines.isEmpty {
                    ContentUnavailableView(
                        tr("No formulas yet"),
                        systemImage: "function",
                        description: Text(tr("Write lines like a = 3, then total = a + 4 in the note."))
                    )
                } else {
                    List(lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "\(line.name) = \(line.expression)")
                                .font(.subheadline)
                            if let value = line.value {
                                Text(verbatim: "= \(ReactiveMath.display(value))")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Color.inkAccent)
                            } else if let problem = line.problem {
                                Text(problem)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("Live Math"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}

extension ReactiveMath {
    static func display(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.4g", value)
    }
}
