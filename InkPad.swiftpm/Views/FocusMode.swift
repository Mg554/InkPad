import PencilKit
import SwiftUI

/// What a finished focus session did, for the wrap-up.
struct FocusSummary: Identifiable {
    let id = UUID()
    let title: String
    let noteID: UUID?
    let seconds: Int
    let pages: Int
    let strokes: Int
    let distractions: [Distraction]
    let cardsReviewed: Int
    let concepts: [String]
}

/// A Focus Mode session: started in a note or on the Focus screen, it
/// runs Flowmodoro and remembers what happened for the wrap-up.
@MainActor
final class FocusSession: ObservableObject {
    static let shared = FocusSession()

    @Published private(set) var isActive = false
    @Published private(set) var title = ""
    @Published var summary: FocusSummary?
    @Published private(set) var startedAt = Date()
    private(set) var noteID: UUID?
    /// The Flowmodoro task the session's stopwatch runs on.
    private var taskID: UUID?
    private var startStrokes = 0
    private var pagesSeen: Set<Int> = []
    private var cardsReviewed = 0
    /// The note's toolbar as it was before Focus Mode hid it.
    var toolbarWasHidden = false
    /// Note editors on screen: the floating Focus pill shows when none is
    /// (each note shows its own Focus bar).
    @Published var openEditors = 0

    /// Seconds focused in this session.
    func elapsed(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt)))
    }

    func start(title: String, noteID: UUID?, strokes: Int, workspace: WorkspaceStore) {
        guard workspace.startFocusSession(title: title), let timer = workspace.flowTimer else { return }
        self.title = title
        self.noteID = noteID
        taskID = timer.taskID
        startedAt = timer.workStartedAt
        startStrokes = strokes
        pagesSeen = []
        cardsReviewed = 0
        isActive = true
    }

    func sawPage(_ page: Int, in note: UUID) {
        if isActive, note == noteID { pagesSeen.insert(page) }
    }

    /// Flowmodoro stopped or switched tasks elsewhere: the session ends too.
    func timerChanged(_ workspace: WorkspaceStore) {
        guard isActive else { return }
        let timer = workspace.flowTimer
        let stillMine: Bool = timer?.taskID == taskID && timer?.phase == .working
        if !stillMine { finish(strokes: nil, concepts: [], workspace: workspace, seconds: nil) }
    }

    func reviewedCard() {
        cardsReviewed += 1
    }

    /// Ends the session: work stops, the break is earned, the wrap-up shows.
    func end(strokes: Int, concepts: [String], workspace: WorkspaceStore) {
        guard isActive else { return }
        let seconds = elapsed(at: Date())
        let timer = workspace.flowTimer
        if timer?.taskID == taskID, timer?.phase == .working { workspace.stopFlowWork() }
        finish(strokes: strokes, concepts: concepts, workspace: workspace, seconds: seconds)
    }

    private func finish(strokes: Int?, concepts: [String], workspace: WorkspaceStore, seconds: Int?) {
        let caught = workspace.distractions.filter { $0.createdAt >= startedAt }
        let made = FocusSummary(
            title: title,
            noteID: noteID,
            seconds: seconds ?? elapsed(at: Date()),
            pages: pagesSeen.count,
            strokes: strokes.map { max($0 - startStrokes, 0) } ?? 0,
            distractions: caught,
            cardsReviewed: cardsReviewed,
            concepts: Array(concepts.prefix(6))
        )
        isActive = false
        // After panels close, so the wrap-up sheet can always show.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            summary = made
        }
    }
}

// MARK: Companion

/// Beside the page while focusing: related notes and concepts, quick
/// questions, and your weak flashcards on the same subject.
struct FocusCompanionView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var ai = AISettings.shared
    @ObservedObject private var living = LivingNotes.shared
    let noteID: UUID
    /// The text of what is open (the page being read, the handwriting).
    let pageText: () -> String

    @State private var questions: [String] = []
    @State private var isAsking = false
    @State private var problem: String?
    @State private var revealed: Set<UUID> = []
    @State private var related: [LivingNotes.Related] = []
    @State private var weakCards: [WeakCard] = []
    @State private var refresh = 0

    private struct WeakCard: Identifiable {
        var id: UUID { card.id }
        let card: Flashcard
        let deckID: UUID
    }

    var body: some View {
        List {
            relatedSection
            questionsSection
            cardsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Worked out once, and again after a card is rated, not on every redraw.
        .task(id: refresh) {
            related = living.related(to: noteID, store: store, limit: 5)
            weakCards = findWeakCards()
        }
    }

    // MARK: Related

    @ViewBuilder
    private var relatedSection: some View {
        let items = related
        Section {
            if items.isEmpty {
                Text("Nothing related yet. Write a little more.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.note(item.id)?.title ?? "Note").font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(item.shared.prefix(4), id: \.self) { name in
                                Button(tr(name)) { CommandCenter.shared.sheet = .concept(LivingAnalyzer.key(for: name)) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                    }
                }
            }
        } header: {
            Label("Related", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    // MARK: Questions

    @ViewBuilder
    private var questionsSection: some View {
        Section {
            ForEach(Array(questions.enumerated()), id: \.offset) { item in
                Text("\(item.offset + 1). \(item.element)").font(.callout)
            }
            if let problem {
                Text(trMessage(problem)).font(.caption).foregroundStyle(.red)
            }
            Button {
                ask()
            } label: {
                if isAsking {
                    ProgressView()
                } else {
                    Label(questions.isEmpty ? "Ask Me Two Questions" : "Two More Questions", systemImage: "questionmark.bubble")
                }
            }
            .disabled(isAsking)
        } header: {
            Label("Quick Check", systemImage: "checkmark.bubble")
        } footer: {
            Text(ai.problem == nil
                 ? "About the page you're on, if the AI Firewall allows it for this note. Answer in your head, or write it."
                 : "Without an AI service, questions come from your flashcards.")
        }
    }

    private func ask() {
        problem = nil
        let text = String(pageText().prefix(6000))
        guard ai.problem == nil, let client = ai.client(), text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 else {
            questions = cardQuestions()
            if questions.isEmpty { problem = "No flashcards on this yet, and no AI service set up." }
            return
        }
        guard store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else {
            questions = cardQuestions()
            problem = NoteTexts.firewallMessage(onDevice: client.kind.isOnDevice)
            return
        }
        isAsking = true
        Task {
            defer { isAsking = false }
            let prompt = [
                "Write two short questions that check understanding of this page, for a student studying it. One recall question and one that applies the idea. Questions only, one per line, no numbering, in the page's language.",
                text,
            ].joined(separator: "\n\n")
            do {
                let reply = try await client.complete(system: "You write short study questions.", messages: [AIMessage(.user, prompt)])
                let lines = reply.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•0123456789.)")) }
                questions = lines.filter { !$0.isEmpty }.prefix(2).map { String($0) }
            } catch {
                problem = error.localizedDescription
                questions = cardQuestions()
            }
        }
    }

    private func cardQuestions() -> [String] {
        Array(weakCards.shuffled().prefix(2).map(\.card.front))
    }

    // MARK: Weak cards

    /// Cards often forgotten, on the subject of this note first.
    private func findWeakCards() -> [WeakCard] {
        let words = Set(BookIndex.words(in: pageText() + " " + (store.note(noteID)?.title ?? "")))
        var scored: [(WeakCard, Int)] = []
        for deck in workspace.flashcardDecks {
            let fromThisNote = deck.sourceNoteIDs.contains(noteID)
            for card in deck.cards where card.lastReviewed != nil && card.box <= 1 {
                let cardWords = Set(BookIndex.words(in: card.front + " " + card.back))
                let overlap = cardWords.intersection(words).count + (fromThisNote ? 5 : 0)
                if overlap > 0 { scored.append((WeakCard(card: card, deckID: deck.id), overlap)) }
            }
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(5).map(\.0)
    }

    @ViewBuilder
    private var cardsSection: some View {
        let cards = weakCards
        Section {
            if cards.isEmpty {
                Text("No weak cards on this subject.").foregroundStyle(.secondary)
            }
            ForEach(cards) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.card.front).font(.callout.weight(.semibold))
                    if revealed.contains(item.id) {
                        Text(item.card.back).font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Again") { rate(item, .again) }.tint(.red)
                            Button("Good") { rate(item, .good) }.tint(.green)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Show Answer") { revealed.insert(item.id) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Label("Weak Cards", systemImage: "rectangle.on.rectangle.angled")
        }
    }

    private func rate(_ item: WeakCard, _ rating: Flashcard.Rating) {
        workspace.review(card: item.card.id, in: item.deckID, rating: rating)
        revealed.remove(item.id)
        FocusSession.shared.reviewedCard()
        refresh += 1
    }
}

// MARK: Wrap-up

/// The end of a focus session: what was done, distractions, and a review
/// to schedule.
struct FocusWrapUpView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let summary: FocusSummary
    @State private var scheduled = false

    /// A review of this already waits in the Planner.
    private var alreadyPlanned: Bool {
        let title = "Review: \(summary.title)"
        return workspace.tasks.contains { $0.title == title && $0.status != .done }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        stat(PlannerInsights.duration(summary.seconds), "focused", .green)
                        if summary.pages > 0 { stat("\(summary.pages)", summary.pages == 1 ? "page" : "pages", .blue) }
                        if summary.strokes > 0 { stat("\(summary.strokes)", "strokes written", .purple) }
                        if summary.cardsReviewed > 0 { stat("\(summary.cardsReviewed)", "cards", .orange) }
                    }
                }
                if !summary.concepts.isEmpty {
                    Section("You Worked With") {
                        Text(summary.concepts.joined(separator: " · ")).font(.callout)
                    }
                }
                Section {
                    if summary.distractions.isEmpty {
                        Label("No distractions caught. Well done.", systemImage: "sparkles").foregroundStyle(.green)
                    }
                    ForEach(summary.distractions) { item in
                        Label(item.text.isEmpty ? "Handwritten thought" : item.text, systemImage: "tray")
                    }
                } header: {
                    Text("Distractions (\(summary.distractions.count))")
                } footer: {
                    if !summary.distractions.isEmpty {
                        Text("They wait in the Distraction Box; turn any into a reminder there.")
                    }
                }
                Section {
                    if alreadyPlanned && !scheduled {
                        Label("A review is already in the Planner", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            scheduleReview()
                        } label: {
                            Label(scheduled ? "Review Planned for Tomorrow" : "Plan a Spaced Review (1, 3, 7 Days)", systemImage: scheduled ? "checkmark.circle.fill" : "calendar.badge.plus")
                        }
                        .disabled(scheduled)
                    }
                } footer: {
                    Text("Adds a review of “\(summary.title)” to the Planner for tomorrow; finishing it plans the next ones.")
                }
            }
            .navigationTitle("Session Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(tr(value)).font(.title3.bold()).foregroundStyle(color)
            Text(trMessage(label)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func scheduleReview() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        var review = PlanTask(title: "Review: \(summary.title)", dueDate: tomorrow)
        review.noteID = summary.noteID
        review.schedulesReviews = true
        review.reviewStep = 1
        review.estimateMinutes = 15
        review.notes = "Review 1 of 3 (spaced repetition), from a focus session."
        workspace.save(review)
        scheduled = true
        CommandCenter.shared.say("Review planned for tomorrow")
    }
}

// MARK: Focus screen

/// Focus Mode on its own: the timer, a scene, the subject's plant growing,
/// sounds, and catching distractions. No note.
struct FocusScreenView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = FocusSession.shared
    @ObservedObject private var looks = FlowLookStore.shared
    @State private var title = ""
    @State private var wrapUp: FocusSummary?
    @State private var isCatching = false
    @State private var subjectSeconds = 0

    var body: some View {
        ZStack {
            ScreenBackdropView(backdrop: scene)
                .ignoresSafeArea()
            if session.isActive {
                running
            } else {
                chooser
            }
        }
        .sheet(item: $wrapUp, onDismiss: { dismiss() }) { summary in
            FocusWrapUpView(summary: summary)
        }
        .sheet(isPresented: $isCatching) {
            DistractionCapture()
        }
        // The wrap-up of a session from this screen (also when Flowmodoro stopped it).
        .onChange(of: session.summary?.id) {
            if let summary = session.summary, summary.noteID == nil {
                wrapUp = summary
                session.summary = nil
            }
        }
    }

    /// The chosen background, or the season when it is the theme's.
    private var scene: ScreenBackdrop {
        if looks.look.backdrop != .theme { return looks.look.backdrop }
        switch PlantPainter.currentSeason {
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        case .winter: return .winter
        case .none: return .glass
        }
    }

    private var suggestions: [String] {
        let planned = PlannerInsights.todayCandidates(workspace.tasks).map { $0.title.isEmpty ? "Untitled" : $0.title }
        let flows = workspace.flowTasks.filter { !$0.isDone }.map(\.title)
        var seen: Set<String> = []
        return (planned + flows).filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    private var chooser: some View {
        VStack(spacing: 22) {
            Text("Focus Mode").font(.largeTitle.bold())
            Text("What will you focus on?").foregroundStyle(.secondary)
            TextField("A task or subject", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .onSubmit(begin)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { item in
                            Button(tr(item)) { title = item }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(minWidth: 620)
                }
                .frame(maxWidth: 620)
            }
            Picker("Sound", selection: $looks.look.ambient) {
                ForEach(FlowLook.Ambient.allCases) { Label(tr($0.title), systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)
            HStack(spacing: 16) {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    begin()
                } label: {
                    Label("Start Focusing", systemImage: "play.fill").frame(minWidth: 180, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding()
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = session.elapsed(at: context.date)
            let plant = GardenPlant(subject: session.title, seconds: subjectSeconds + seconds)
            VStack(spacing: 18) {
                Text(tr(session.title)).font(.title2.weight(.semibold))
                FlowTimerFace(face: looks.look.face, seconds: seconds, progress: Double(seconds % 3600) / 3600, tint: .green, label: "Focus")
                    .styledGlow(looks.look.glow, color: .green)
                GardenPlantCard(plant: plant, size: 110)
                HStack(spacing: 14) {
                    Button {
                        // The session keeps running; the Focus pill brings this back.
                        dismiss()
                    } label: {
                        Label("Open My Notes", systemImage: "books.vertical")
                    }
                    .buttonStyle(.bordered)
                    FocusSoundMenu()
                    Button {
                        isCatching = true
                    } label: {
                        Label("Catch a Distraction", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Button(role: .destructive) {
                        finish()
                    } label: {
                        Label("End Session", systemImage: "stop.fill").frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
        .padding()
    }

    /// Focus already logged on this subject, so the plant starts where it was.
    private func loggedSeconds(for subject: String) -> Int {
        let plants = GardenPlant.garden(sessions: workspace.flowSessions, tasks: workspace.tasks)
        let mine: GardenPlant? = plants.first(where: { $0.subject == subject })
        return mine?.seconds ?? 0
    }

    private func begin() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        subjectSeconds = loggedSeconds(for: name)
        session.start(title: name, noteID: nil, strokes: 0, workspace: workspace)
    }

    private func finish() {
        session.end(strokes: 0, concepts: [], workspace: workspace)
    }
}

/// While a focus session runs outside a note: the time, the sound, back to
/// the Focus screen, or end.
struct FocusPill: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var session = FocusSession.shared

    var body: some View {
        HStack(spacing: 12) {
            Button {
                CommandCenter.shared.showsFocusScreen = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope").foregroundStyle(.green)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Flowmodoro.clock(session.elapsed(at: context.date)))
                            .font(.headline.monospacedDigit())
                    }
                    Text(verbatim: session.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 180)
                }
            }
            .buttonStyle(.plain)
            FocusSoundMenu()
            Button {
                CommandCenter.shared.sheet = .catchDistraction
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .accessibilityLabel("Catch a Distraction")
            Button("End", role: .destructive) {
                session.end(strokes: 0, concepts: [], workspace: workspace)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

/// A quick sound switch while focusing.
struct FocusSoundMenu: View {
    @ObservedObject private var looks = FlowLookStore.shared
    @ObservedObject private var own = OwnSoundStore.shared

    var body: some View {
        Menu {
            Button {
                choose(key: nil, ambient: .off)
            } label: {
                Label("Off", systemImage: "speaker.slash")
            }
            Section("Nature") {
                ForEach(NatureSound.allCases) { sound in
                    Button {
                        choose(key: sound.key, ambient: looks.look.ambient)
                    } label: {
                        Label(tr(sound.title), systemImage: sound.systemImage)
                    }
                }
            }
            Section("Made on This iPad") {
                ForEach(FlowLook.Ambient.allCases.filter { $0 != .off }) { ambient in
                    Button {
                        choose(key: nil, ambient: ambient)
                    } label: {
                        Label(tr(ambient.title), systemImage: ambient.systemImage)
                    }
                }
            }
            if !own.sounds.isEmpty {
                Section("My Sounds") {
                    ForEach(own.sounds) { sound in
                        Button {
                            choose(key: sound.key, ambient: looks.look.ambient)
                        } label: {
                            Label { Text(verbatim: sound.name) } icon: { Image(systemName: "music.note") }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: FocusSounds.systemImage(of: looks.look))
        }
        .accessibilityLabel("Sound")
    }

    private func choose(key: String?, ambient: FlowLook.Ambient) {
        looks.look.soundKey = key
        looks.look.ambient = ambient
        FocusSoundController.update()
    }
}
