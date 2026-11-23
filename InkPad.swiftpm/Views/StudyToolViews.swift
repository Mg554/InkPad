import PencilKit
import SwiftUI

struct NoteIDBox: Identifiable {
    let id: UUID
}

/// Write everything you remember about a note, then see what you missed.
struct RecallSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var source = ""
    @State private var ink = PKDrawing()
    @State private var result: RecallEngine.Result?
    @State private var isReading = true
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let result {
                        HStack {
                            Text(trStudyFmt("You recalled {}% of the key words.", String(Int(RecallEngine.recallScore(result) * 100))))
                                .font(.headline)
                            Spacer()
                            Text("\(result.missed.count)/\(result.sourceCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if result.missed.isEmpty {
                            Label("You got everything.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(result.missed.joined(separator: " · "))
                                .font(.caption)
                        }
                        Button("Add Missed Words to Flashcards") { saveCards(result) }
                        if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(.green) }
                    } else {
                        Text("Write from memory first, then compare with the note.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recall Result")
                }

                Section {
                    CalculatorCanvas(drawing: $ink)
                        .frame(height: 260)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Button {
                        check()
                    } label: {
                        Label("Check My Recall", systemImage: "checkmark.circle")
                    }
                    .disabled(ink.strokes.isEmpty || isReading)
                } header: {
                    Text("Blank Page")
                } footer: {
                    Text("The note is hidden while you write. Everything is read on this iPad.")
                }
            }
            .navigationTitle("Blank-Page Recall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                source = await NoteTexts.text(of: noteID, store: store)
                isReading = false
            }
        }
    }

    private func check() {
        let drawing = ink
        Task {
            let written = await Task.detached(priority: .utility) {
                MindSketchReader.readText(drawing)
            }.value
            result = RecallEngine.evaluate(source: source, written: written)
        }
    }

    private func saveCards(_ result: RecallEngine.Result) {
        guard !result.missed.isEmpty else { return }
        let cards = result.missed.map { Flashcard(front: trStudyWord($0), back: $0) }
        let deck = FlashcardDeck(
            id: UUID(), title: tr("Recall Gaps"), sourceNoteIDs: [noteID], cards: cards,
            createdAt: Date(), modifiedAt: Date()
        )
        workspace.save(deck)
        savedMessage = trStudyFmt("{} cards added to Flashcards.", String(cards.count))
    }

    private func trStudyWord(_ word: String) -> String {
        trMessage("What does “{}” mean?").replacingOccurrences(of: "{}", with: word)
    }
}

/// One-tap capture into the daily note. No title, folder or tag decision.
struct QuickCaptureSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var ink = PKDrawing()
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Thought, task or note…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    CalculatorCanvas(drawing: $ink)
                        .frame(height: 180)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Handwriting is read on this iPad and added with your typed words.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).foregroundStyle(.green) } }
            }
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { capture() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ink.strokes.isEmpty)
                }
            }
        }
    }

    private func capture() {
        let drawing = ink
        Task {
            var words = text
            if drawing.strokes.count > 0 {
                let read = await Task.detached(priority: .utility) { MindSketchReader.readText(drawing) }.value
                if !read.isEmpty { words = words.isEmpty ? read : words + "\n" + read }
            }
            let note = QuickCapture.dailyNote(in: store) ?? store.createTextNote(titled: "Daily Note", in: nil)
            guard let id = note?.id else { return }
            message = QuickCapture.append(words, to: id, store: store)
                ? tr("Added to Today's Note.")
                : tr("Nothing was added.")
            if message?.contains("Added") == true {
                try? await Task.sleep(for: .milliseconds(350))
                dismiss()
            }
        }
    }
}

/// Active-recall activities generated offline from a note's own words.
struct ActivitySheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var kind: ActivityKind = .fillBlank
    @State private var activities: [RecallActivity] = []
    @State private var revealed: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Picker("Activity", selection: $kind) {
                    ForEach(ActivityKind.allCases) { Label(tr($0.title), systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, _ in rebuild() }

                Section {
                    if activities.isEmpty {
                        Text("This note does not have enough text for this activity yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activities) { activity in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: activity.prompt).font(.subheadline)
                            if !activity.choices.isEmpty {
                                Text(activity.choices.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if revealed.contains(activity.id) {
                                Text(verbatim: activity.answer)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Color.inkAccent)
                            } else {
                                Button("Show Answer") { revealed.insert(activity.id) }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Active Recall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { rebuild() }
        }
    }

    private func rebuild() {
        Task {
            var text = await NoteTexts.text(of: noteID, store: store)
            if text.isEmpty { text = store.note(noteID)?.title ?? "" }
            activities = ActivityEngine.make(kind, from: text)
            revealed = []
        }
    }
}

/// One action after a lecture recording: notes, cards and questions.
struct LecturePackSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var ai = AISettings.shared
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var pack: LecturePack?
    @State private var isWorking = false
    @State private var problem: String?
    @State private var saved: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        build()
                    } label: {
                        Label(isWorking ? "Building…" : "Build Study Pack", systemImage: "sparkles.rectangle.stack")
                    }
                    .disabled(isWorking || ai.problem != nil)
                    if let problem { Text(problem).foregroundStyle(.orange).font(.caption) }
                    if let aiProblem = ai.problem { Text(aiProblem).font(.caption).foregroundStyle(.orange) }
                } footer: {
                    Text("Uses the connected AI and the AI Firewall. The recording's transcript stays on this iPad.")
                }

                if let pack {
                    Section("Notes") { Text(verbatim: pack.summary).font(.subheadline) }
                    Section("Flashcards") {
                        ForEach(pack.cards) { card in
                            VStack(alignment: .leading) {
                                Text(verbatim: card.front).font(.subheadline.weight(.semibold))
                                Text(verbatim: card.back).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Questions") {
                        ForEach(pack.questions) { question in
                            Text(verbatim: question.question).font(.subheadline)
                        }
                    }
                    Section {
                        Button("Save to Library") { save(pack) }
                        if let saved { Text(saved).font(.caption).foregroundStyle(.green) }
                    }
                }
            }
            .navigationTitle("Lecture Study Pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func build() {
        guard let client = ai.client(for: .study) else { return }
        guard store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else {
            problem = NoteTexts.firewallMessage(onDevice: client.kind.isOnDevice)
            return
        }
        isWorking = true
        problem = nil
        Task {
            defer { isWorking = false }
            let text = await NoteTexts.text(of: noteID, store: store)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                problem = tr("There is no text to study yet.")
                return
            }
            do {
                pack = try await LecturePackEngine.build(text: text, client: client)
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func save(_ pack: LecturePack) {
        let title = store.note(noteID)?.title ?? "Lecture"
        let note = store.createTextNote(titled: title + " · Study Pack", in: nil, extraText: pack.summary)
        let deck = FlashcardDeck(
            id: UUID(), title: title + " · Cards", sourceNoteIDs: [noteID], cards: pack.cards,
            createdAt: Date(), modifiedAt: Date()
        )
        workspace.save(deck)
        let quiz = Quiz(
            id: UUID(), title: title + " · Questions", sourceNoteIDs: [noteID],
            questions: pack.questions, bestScore: nil, createdAt: Date()
        )
        workspace.save(quiz)
        saved = note != nil
            ? tr("Saved a note, flashcards and questions.")
            : tr("Saved flashcards and questions.")
    }
}

/// Link stations so the GPS can warn about weak foundations.
struct PrerequisiteSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State var map: KnowledgeMap

    var body: some View {
        NavigationStack {
            List {
                let warnings = map.foundationWarnings(workspace: workspace)
                if !warnings.isEmpty {
                    Section("Weak Foundations") {
                        ForEach(warnings, id: \.station.id) { item in
                            Label(trStudy(item.blocker), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                ForEach(map.stations) { station in
                    Section {
                        ForEach(map.stations) { other in
                            if other.id != station.id {
                                Toggle(isOn: Binding(
                                    get: { station.prerequisiteIDs.contains(other.id) },
                                    set: { on in setPrerequisite(on, for: station.id, other: other.id) }
                                )) {
                                    Text(verbatim: other.title)
                                }
                            }
                        }
                    } header: {
                        Text(station.title)
                    }
                }
            }
            .navigationTitle("Prerequisites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func setPrerequisite(_ on: Bool, for stationID: UUID, other: UUID) {
        guard let index = map.stations.firstIndex(where: { $0.id == stationID }) else { return }
        var list = map.stations[index].prerequisiteIDs
        if on {
            if !list.contains(other) { list.append(other) }
        } else {
            list.removeAll { $0 == other }
        }
        map.stations[index].prerequisiteIDs = list
        workspace.save(map)
    }
}

private func trStudy(_ pattern: String) -> String {
    trMessage(pattern)
}

private func trStudyFmt(_ pattern: String, _ value: String) -> String {
    trMessage(pattern).replacingOccurrences(of: "{}", with: value)
}

/// Flags weak flashcards so they can be rewritten, not just repeated.
struct CardQualitySheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    private var issues: [CardQuality] { FlashcardQuality.issues(in: workspace.flashcardDecks) }

    var body: some View {
        NavigationStack {
            List {
                if issues.isEmpty {
                    ContentUnavailableView {
                        Label("Cards Look Clear", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("No short or bare-answer cards were found.")
                    }
                }
                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: issue.front).font(.subheadline.weight(.semibold))
                        Text(issue.reason).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section {
                    Text("A good card asks one clear question and answers it in a full sentence, with enough context to stand alone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Card Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Turns focus time, recall and quiz scores into an efficiency report.
struct LearningReportSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var metrics: [LearningMetric] = []

    var body: some View {
        NavigationStack {
            List {
                if metrics.isEmpty {
                    Text("No study data yet.").foregroundStyle(.secondary)
                }
                ForEach(metrics) { metric in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.title).font(.subheadline.weight(.semibold))
                            Text(metric.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(metric.value).font(.title3.weight(.semibold)).foregroundStyle(Color.inkAccent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Learning Efficiency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { metrics = LearningStats.report(workspace: workspace) }
        }
    }
}
