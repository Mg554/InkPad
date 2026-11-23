import PencilKit
import SwiftUI

/// The home of the nine insight tools. Everything here works on the iPad,
/// offline unless a tool explicitly asks the connected AI service.
struct InsightHubView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @ObservedObject private var ai = AISettings.shared
    @ObservedObject private var postcards = PostcardStore.shared
    @State private var settings = InsightSettings.load()
    @State private var doctor: DoctorReport?
    @State private var isChecking = false
    @State private var frictionNote: UUID?
    @State private var friction: FrictionReport?
    @State private var macroName = ""
    @State private var macroAction: MacroAction = .task
    @State private var macroInk = PKDrawing()
    @State private var isMakingMacro = false
    @State private var postcardNote: UUID?
    @State private var postcardText = ""
    @State private var debateA: UUID?
    @State private var debateB: UUID?
    @State private var debatePoints: [DebatePoint]?
    @State private var isDebating = false
    @State private var debateProblem: String?
    @State private var questionNote: UUID?
    @State private var questionText = ""
    @State private var questionDays = 1
    @State private var isComposingQuestion = false
    @State private var picker: InsightPicker?
    @State private var answerText = ""
    @State private var answering: UUID?

    private enum InsightPicker: Identifiable {
        case friction, postcard, debateA, debateB, question

        var id: Int {
            switch self {
            case .friction: 0
            case .postcard: 1
            case .debateA: 2
            case .debateB: 3
            case .question: 4
            }
        }
    }

    var body: some View {
        List {
            introSection
            doctorSection
            writingSection
            confidenceSection
            frictionSection
            macroSection
            marginaliaSection
            postcardSection
            debateSection
            examSection
        }
        .navigationTitle("InkPad Insights")
        .navigationBarTitleDisplayMode(.inline)
        .themedBackground()
        .onAppear { postcards.refresh() }
        .onChange(of: settings) { settings.save() }
        .sheet(item: $picker) { kind in
            NotePickerSheet(excluding: nil, title: "Choose a Note") { id in picked(id, for: kind) }
                .environmentObject(store)
        }
        .sheet(isPresented: $isMakingMacro) { macroSheet }
        .alert("Answer Your Future Self", isPresented: Binding(
            get: { answering != nil }, set: { if !$0 { answering = nil } }
        )) {
            TextField("Your answer", text: $answerText)
            Button("Save") { saveAnswer() }
            Button("Cancel", role: .cancel) { answering = nil }
        }
        .alert("Question for Future Me", isPresented: $isComposingQuestion) {
            TextField("Question", text: $questionText)
            Button("Save") { saveQuestion() }
            Button("Cancel", role: .cancel) { isComposingQuestion = false }
        }
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label("Tools that read your own writing", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                Text("They work from the ink and notes already on this iPad. Nothing leaves the device unless you ask the AI, and the AI Firewall still decides.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Doctor

    private var doctorSection: some View {
        Section {
            Button {
                runDoctor()
            } label: {
                Label(isChecking ? "Checking…" : "Run a Library Check", systemImage: "stethoscope")
            }
            .disabled(isChecking)
            if let doctor {
                if doctor.findings.isEmpty {
                    Label("Your library looks healthy.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(trMessage("{} things to look at").replacingOccurrences(of: "{}", with: String(doctor.findings.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(doctor.findings.prefix(30))) { finding in
                        Button {
                            if let id = finding.noteID { navigation.openNote(id) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                                Image(systemName: finding.kind.symbol)
                                    .foregroundStyle(Color.inkAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr(finding.kind.title))
                                        .font(.subheadline.weight(.semibold))
                                    Text(verbatim: finding.title).font(.caption)
                                    Text(finding.detail).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(finding.noteID == nil)
                    }
                }
            }
        } header: {
            Label("Note Doctor", systemImage: "heart.text.square")
        } footer: {
            Text("Finds stale notes, words without flashcards, weak concepts and handwriting that has not been read yet. Runs entirely on this iPad.")
        }
    }

    private func runDoctor() {
        isChecking = true
        Task {
            let report = DoctorReport.make(store: store, workspace: workspace)
            doctor = report
            isChecking = false
        }
    }

    // MARK: Time-lapse

    private var writingSection: some View {
        Section {
            LabeledContent("Writing Time-Lapse") {
                Image(systemName: "film.stack")
            }
            Text("Open a handwritten note, then More › Writing Time-Lapse to watch the page fill in stroke by stroke and export it as an animated GIF. Every PencilKit stroke already carries the moment it was written.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                if let note = store.notes.first(where: { !$0.isText }) { navigation.openNote(note.id) }
            } label: {
                Label("Open a Note to Try It", systemImage: "square.and.pencil")
            }
        } header: {
            Label("Writing Tools", systemImage: "pencil.and.scribble")
        }
    }

    // MARK: Confidence

    private var confidenceSection: some View {
        Section {
            Toggle("Confidence Ink", isOn: $settings.confidenceInk)
            Text("More › Confidence Ink on a page lays a color map over the handwriting: red where the matching flashcards are being forgotten, green where they are remembered. Tap a line to light it up on the page.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.md) {
                confidenceChip(.weak)
                confidenceChip(.learning)
                confidenceChip(.strong)
                confidenceChip(.unknown)
            }
        } header: {
            Label("Understanding", systemImage: "chart.bar.doc.horizontal")
        }
    }

    private func confidenceChip(_ level: ConfidenceLevel) -> some View {
        HStack(spacing: 4) {
            Circle().fill(confidenceColor(level)).frame(width: 8, height: 8)
            Text(tr(level.title)).font(.caption2)
        }
    }

    private func confidenceColor(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .weak: .red
        case .learning: .orange
        case .strong: .green
        case .unknown: .secondary
        }
    }

    // MARK: Friction

    private var frictionSection: some View {
        Section {
            Toggle("Track Friction", isOn: $settings.frictionTracking)
            Button {
                picker = .friction
            } label: {
                Label("Find the Hard Parts of a Note…", systemImage: "waveform.path.ecg")
            }
            if let friction {
                HStack {
                    StatTile(value: String(friction.totalStrokes), label: "strokes")
                    StatTile(value: String(friction.pauses), label: "long pauses")
                    StatTile(value: String(format: "%.0fm", friction.longestPause / 60), label: "longest")
                }
                ForEach(friction.points.prefix(12)) { point in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page \(point.page + 1) · \(tr(point.title))")
                            .font(.subheadline.weight(.semibold))
                        Text(point.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("Friction Map", systemImage: "waveform.path.ecg")
        } footer: {
            Text("PencilKit deletes erased strokes, so the map reads the traces an erasure leaves: long pauses and lines written over several times.")
        }
    }

    private func analyzeFriction(_ id: UUID) {
        guard let content = try? store.loadContent(for: id) else { return }
        friction = FrictionEngine.make(drawing: content.drawing, background: content.makeBackground())
    }

    // MARK: Macros

    private var macroSection: some View {
        Section {
            ForEach(settings.macros) { macro in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: macro.action.symbol)
                        .foregroundStyle(Color.inkAccent)
                    VStack(alignment: .leading) {
                        Text(verbatim: macro.name).font(.subheadline)
                        Text(tr(macro.action.title)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        settings.macros.removeAll { $0.id == macro.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                macroInk = PKDrawing()
                macroName = ""
                isMakingMacro = true
            } label: {
                Label("Draw a New Pencil Macro…", systemImage: "scribble.variable")
            }
        } header: {
            Label("Pencil Macros", systemImage: "command")
        } footer: {
            Text("Draw a small shape, give it a name and choose an action. In a note, More › Run Pencil Macro reads the shape you draw and runs its action.")
        }
    }

    private var macroSheet: some View {
        NavigationStack {
            Form {
                Section("Your Shape") {
                    CalculatorCanvas(drawing: $macroInk)
                        .frame(height: 220)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Draw a simple shape, like a check, a star or a wavy line.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Name") {
                    TextField("Name", text: $macroName)
                    Picker("Action", selection: $macroAction) {
                        ForEach(MacroAction.allCases) { action in
                            Label(tr(action.title), systemImage: action.symbol).tag(action)
                        }
                    }
                }
            }
            .navigationTitle("New Pencil Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isMakingMacro = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveMacro() }
                        .disabled(macroInk.strokes.isEmpty || macroName.trimmed.isEmpty)
                }
            }
        }
    }

    private func saveMacro() {
        let points = MacroEngine.normalize(macroInk)
        guard !points.isEmpty else { return }
        settings.macros.append(PencilMacro(name: macroName.trimmed, action: macroAction, points: points))
        isMakingMacro = false
    }

    // MARK: Marginalia

    private var marginaliaSection: some View {
        Section {
            ForEach(workspace.marginalia.sorted(by: { $0.due < $1.due }).prefix(12)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.text).font(.subheadline)
                    HStack {
                        Text(store.note(item.noteID)?.title ?? "Note")
                        Text("·")
                        Text(item.answeredAt == nil ? item.due.formatted(date: .abbreviated, time: .omitted) : "Answered")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if let answer = item.answer {
                        Text(verbatim: answer).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if item.answeredAt == nil {
                        answerText = item.answer ?? ""
                        answering = item.id
                    }
                }
            }
            Button {
                picker = .question
            } label: {
                Label("Leave a Question for Future Me…", systemImage: "clock.badge.questionmark")
            }
            Stepper(value: $questionDays, in: 1...30) {
                Text("Ask again in \(questionDays) days").font(.caption)
            }
        } header: {
            Label("Future-Me Marginalia", systemImage: "calendar.badge.clock")
        } footer: {
            Text("A question waits in the margin of the page it came from. Answer it with the pen or here, then it is done.")
        }
    }

    private func saveAnswer() {
        guard let id = answering else { return }
        workspace.answerFutureMe(id, answer: answerText)
        answering = nil
    }

    private func saveQuestion() {
        guard let noteID = questionNote, !questionText.trimmed.isEmpty else { return }
        let due = Calendar.current.date(byAdding: .day, value: questionDays, to: Date()) ?? Date()
        workspace.askFutureMe(MarginalQuestion(noteID: noteID, text: questionText.trimmed, due: due))
        isComposingQuestion = false
    }

    private func sendPostcard() {
        guard let noteID = postcardNote, postcards.problem == nil else { return }
        guard store.aiAccess(of: noteID) != .never else {
            CommandCenter.shared.say(tr("Notes set to Never under the AI Firewall can't be sent as postcards."))
            return
        }
        postcards.send(noteID: noteID, page: 0, text: postcardText, author: settings.postcardAuthor)
        postcardText = ""
    }

    // MARK: Postcards

    private var postcardSection: some View {
        Section {
            if postcards.problem != nil {
                Text(postcards.problem ?? "").font(.caption).foregroundStyle(.orange)
            }
            ForEach(postcards.cards.prefix(12)) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: card.text).font(.subheadline)
                    HStack {
                        Text(verbatim: card.author)
                        Text("·")
                        Text(card.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Button {
                        navigation.openNote(card.noteID)
                    } label: {
                        Text(store.note(card.noteID)?.title ?? "Open Note")
                            .font(.caption)
                    }
                }
            }
            Button {
                picker = .postcard
            } label: {
                Label("Write a Postcard to Another iPad…", systemImage: "envelope")
            }
            if postcardNote != nil {
                TextField("Message", text: $postcardText, axis: .vertical)
                    .lineLimit(2...5)
                Button {
                    sendPostcard()
                } label: {
                    Label("Send Postcard", systemImage: "paperplane")
                }
                .disabled(postcardText.trimmed.isEmpty)
            }
            TextField("From (optional)", text: $settings.postcardAuthor)
        } header: {
            Label("Offline Postcards", systemImage: "envelope")
        } footer: {
            Text("Postcards travel through the free sync folder you chose in Settings. No account and no server. Notes set to “Never” under the AI Firewall are not sent.")
        }
    }

    // MARK: Debate

    private var debateSection: some View {
        Section {
            Button {
                picker = .debateA
            } label: {
                HStack {
                    Text("First note").foregroundStyle(Color.primary)
                    Spacer()
                    Text(verbatim: store.note(debateA ?? UUID())?.title ?? "Choose…")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                picker = .debateB
            } label: {
                HStack {
                    Text("Second note").foregroundStyle(Color.primary)
                    Spacer()
                    Text(verbatim: store.note(debateB ?? UUID())?.title ?? "Choose…")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                runDebate()
            } label: {
                Label(isDebating ? "Comparing…" : "Find Contradictions", systemImage: "person.2.badge.gearshape")
            }
            .disabled(debateA == nil || debateB == nil || isDebating)
            if let problem = debateProblem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            if let points = debatePoints {
                if points.isEmpty {
                    Label("These notes agree.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ForEach(points) { point in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: point.noteID == debateA ? "A" : "B")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.inkAccent)
                            Text(verbatim: point.text).font(.subheadline)
                        }
                    }
                }
            }
        } header: {
            Label("Cross-Note Debate", systemImage: "bubble.left.and.bubble.right")
        } footer: {
            Text("Compares two notes about the same subject and lists only real disagreements. Requires an AI service, and never reads notes the AI Firewall blocks.")
        }
    }

    private func runDebate() {
        guard let first = debateA, let second = debateB else { return }
        guard ai.problem == nil, let client = ai.client() else {
            debateProblem = ai.problem ?? tr("No AI service is set up.")
            return
        }
        guard store.mayUseAI(first, onDevice: client.kind.isOnDevice),
              store.mayUseAI(second, onDevice: client.kind.isOnDevice) else {
            debateProblem = NoteTexts.firewallMessage(onDevice: client.kind.isOnDevice)
            return
        }
        isDebating = true
        debateProblem = nil
        Task {
            defer { isDebating = false }
            let textA = await NoteTexts.text(of: first, store: store)
            let textB = await NoteTexts.text(of: second, store: store)
            let sources = [
                StudySource(id: first, title: store.note(first)?.title ?? "A", text: textA),
                StudySource(id: second, title: store.note(second)?.title ?? "B", text: textB),
            ]
            do {
                debatePoints = try await DebateEngine.compare(sources: sources, client: client)
            } catch {
                debateProblem = error.localizedDescription
            }
        }
    }

    // MARK: Exam

    private var examSection: some View {
        Section {
            Text("In a note, More › Closed-Book Exam starts a timed session: the tools hide, the command palette and AI study tools stop answering, and when time is up InkPad leaves a review task and a sticky on the page.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                if let note = store.notes.first(where: { !$0.isText }) { navigation.openNote(note.id) }
            } label: {
                Label("Open a Note to Start an Exam", systemImage: "timer")
            }
        } header: {
            Label("Exam Mode", systemImage: "book.closed")
        }
    }

    // MARK: Picker

    private func picked(_ id: UUID, for kind: InsightPicker) {
        switch kind {
        case .friction:
            frictionNote = id
            analyzeFriction(id)
        case .postcard:
            postcardNote = id
            postcardText = "Look at page \(1) — "
        case .debateA:
            debateA = id
        case .debateB:
            debateB = id
        case .question:
            questionNote = id
            questionText = "What do I still not understand about \(store.note(id)?.title ?? "this note")?"
            isComposingQuestion = true
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
