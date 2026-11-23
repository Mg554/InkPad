import PencilKit
import SwiftUI

/// A mixed, timed practice exam built from the quiz banks and flashcards in
/// the library. Answers are written with the Pencil and graded on the iPad.
struct ExamSimulatorView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var answers: [ExamAnswer] = []
    @State private var ink: [UUID: PKDrawing] = [:]
    @State private var typed: [UUID: String] = [:]
    @State private var finished = false
    @State private var minutes = 20
    @State private var endsAt = Date()
    @State private var remaining = 0
    private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var score: Double {
        guard !answers.isEmpty else { return 0 }
        return answers.reduce(0) { $0 + $1.score } / Double(answers.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if answers.isEmpty {
                    ContentUnavailableView {
                        Label("No Questions Yet", systemImage: "doc.badge.gearshape")
                    } description: {
                        Text("Make flashcards or quizzes in Study with AI first, then come back for a mixed exam.")
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Label("Ends in \(Flowmodoro.clock(max(remaining, 0)))", systemImage: "timer")
                                Spacer()
                                if finished {
                                    Text(trMessage("Score {}%", String(Int(score * 100))))
                                        .font(.headline)
                                        .foregroundStyle(score >= 0.7 ? Color.green : Color.orange)
                                }
                            }
                        }
                        ForEach(answers) { answer in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: answer.question).font(.subheadline.weight(.semibold))
                                TextField("Answer (optional)", text: binding(for: answer.id))
                                    .textFieldStyle(.roundedBorder)
                                CalculatorCanvas(drawing: drawingBinding(for: answer.id))
                                    .frame(height: 110)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                if finished {
                                    HStack {
                                        Text(verbatim: answer.expected)
                                            .font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(answer.score * 100))%")
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Exam Simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if !answers.isEmpty {
                        Button(finished ? "Again" : "Grade") {
                            if finished { build() } else { grade() }
                        }
                    }
                }
            }
            .onAppear { build() }
            .onReceive(timer) { _ in
                guard !answers.isEmpty, !finished else { return }
                remaining = max(Int(endsAt.timeIntervalSince(Date())), 0)
                if remaining == 0 { grade() }
            }
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(get: { typed[id] ?? "" }, set: { typed[id] = $0 })
    }

    private func drawingBinding(for id: UUID) -> Binding<PKDrawing> {
        Binding(get: { ink[id] ?? PKDrawing() }, set: { ink[id] = $0 })
    }

    private func build() {
        answers = ExamSimulator.build(workspace: workspace, store: store)
        ink = [:]
        typed = [:]
        finished = false
        remaining = minutes * 60
        endsAt = Date().addingTimeInterval(TimeInterval(remaining))
    }

    private func grade() {
        var graded = answers
        for index in graded.indices {
            let id = graded[index].id
            var text = typed[id] ?? ""
            let drawing = ink[id] ?? PKDrawing()
            if drawing.strokes.count > 0 {
                let read = MindSketchReader.readText(drawing)
                if !read.isEmpty { text += (text.isEmpty ? "" : "\n") + read }
            }
            graded[index].written = text
            graded[index].grade()
        }
        answers = graded
        finished = true
    }
}

private func trMessage(_ pattern: String, _ value: String) -> String {
    trMessage(pattern).replacingOccurrences(of: "{}", with: value)
}
