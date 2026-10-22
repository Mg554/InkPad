import SwiftUI

/// Study with AI, like Notability's: chat with your notes, flashcards with
/// spaced review, quizzes, smart notes (summaries) and slides, for every
/// note or the ones you pick.
struct StudyView: View {
    enum Route: Hashable {
        case chat(String)
        /// `nil` reviews the cards due in every deck.
        case review(UUID?)
        case quiz(UUID)
    }

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared

    /// Notes open in an editor, with ink not saved yet.
    let liveContent: [UUID: NoteContent]
    /// Shown as a sheet over a note, with a Done button.
    let isSheet: Bool

    @State private var sources: [UUID]
    @State private var path: [Route] = []
    @State private var question = ""
    @State private var stage: String?
    @State private var message: String?
    @State private var createdNoteID: UUID?
    @State private var isPickingNotes = false
    @State private var isShowingSettings = false
    @State private var isCreatingSlides = false
    @State private var deckToDelete: FlashcardDeck?

    init(sources: [UUID] = [], liveContent: [UUID: NoteContent] = [:], isSheet: Bool = false) {
        _sources = State(initialValue: sources)
        self.liveContent = liveContent
        self.isSheet = isSheet
    }

    private var scopeTitle: String {
        switch sources.count {
        case 0: return "All Notes"
        case 1: return store.note(sources[0])?.title ?? "1 Note"
        default: return "\(sources.count) Notes"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let problem = ai.problem {
                        setupCard(problem)
                    }
                    chatCard
                    reviewCard
                    scopeCard
                    toolsCard
                    if !workspace.flashcardDecks.isEmpty || !workspace.quizzes.isEmpty {
                        savedSection
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Study")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("AI Settings", systemImage: "gearshape")
                    }
                    if isSheet {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .chat(first):
                    StudyChatView(sources: sources, liveContent: liveContent, firstQuestion: first)
                case let .review(deckID):
                    FlashcardReviewView(deckID: deckID)
                case let .quiz(quizID):
                    QuizView(quizID: quizID)
                }
            }
            .overlay {
                if let stage {
                    progressCard(stage)
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            AISettingsView()
        }
        .sheet(isPresented: $isPickingNotes) {
            NotePicker(selection: $sources)
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $isCreatingSlides) {
            DeckGeneratorView(sources: sources.isEmpty ? store.notes(in: .allNotes).prefix(5).map(\.id) : sources, liveContent: liveContent)
                .environmentObject(store)
                .environmentObject(workspace)
        }
        .alert(
            "Study",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil; createdNoteID = nil } })
        ) {
            if let createdNoteID {
                Button("Open") {
                    if isSheet { dismiss() }
                    let id = createdNoteID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { navigation.openNote(id) }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Delete \"\(deckToDelete?.title ?? "")\"?",
            isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }),
            titleVisibility: .visible,
            presenting: deckToDelete
        ) { deck in
            Button("Delete Flashcards", role: .destructive) { workspace.deleteFlashcardDeck(deck.id) }
        }
    }

    // MARK: Cards

    private func setupCard(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect an AI service")
                    .font(.headline)
                Text(problem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open AI Settings") { isShowingSettings = true }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glowCard(.purple)
    }

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat with your notes")
                .font(.title2.bold())
            Text("Ask questions, explore topics and study with \(sources.isEmpty ? "all of your notes" : scopeTitle).")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Ask anything", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .onSubmit(ask)
                Button(action: ask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ai.isReady)
                .accessibilityLabel("Ask")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.teal.opacity(0.35)))
        }
        .padding(20)
        .glowCard(.teal, isActive: false)
    }

    private var reviewCard: some View {
        let due = workspace.dueCardCount
        return Button {
            path.append(.review(nil))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(due > 0 ? "Keep it up!" : "All caught up")
                        .font(.headline)
                    Text(due > 0 ? "\(due) flashcards ready for review" : "No flashcards are due. Make some from your notes below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glowCard(.orange, isActive: due > 0)
        }
        .buttonStyle(PressableStyle())
        .disabled(due == 0)
    }

    private var scopeCard: some View {
        Button {
            isPickingNotes = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.indent")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select study content")
                        .font(.headline)
                    Text("Studying: \(scopeTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .glowCard(.indigo, isActive: false)
        }
        .buttonStyle(PressableStyle())
    }

    private var toolsCard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
            toolButton("Flashcards", systemImage: "rectangle.stack.badge.plus", tint: .orange, action: makeFlashcards)
            toolButton("Quiz", systemImage: "checklist", tint: .green, action: makeQuiz)
            toolButton("Smart Notes", systemImage: "doc.text.magnifyingglass", tint: .purple, action: makeSmartNotes)
            Button {
                isCreatingSlides = true
            } label: {
                toolLabel("Slides", systemImage: "rectangle.on.rectangle.angled", tint: .blue)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func toolButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolLabel(title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(PressableStyle())
        .disabled(!ai.isReady || stage != nil)
    }

    private func toolLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .glowCard(tint, isActive: false)
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !workspace.flashcardDecks.isEmpty {
                Text("Flashcards")
                    .font(.headline)
                    .padding(.top, 6)
                ForEach(workspace.flashcardDecks.sorted { $0.modifiedAt > $1.modifiedAt }) { deck in
                    Button {
                        path.append(.review(deck.id))
                    } label: {
                        savedRow(deck.title, detail: "\(deck.cards.count) cards · \(deck.dueCount) due", systemImage: "rectangle.on.rectangle", tint: .orange)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            deckToDelete = deck
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            if !workspace.quizzes.isEmpty {
                Text("Quizzes")
                    .font(.headline)
                    .padding(.top, 6)
                ForEach(workspace.quizzes.sorted { $0.createdAt > $1.createdAt }) { quiz in
                    Button {
                        path.append(.quiz(quiz.id))
                    } label: {
                        savedRow(
                            quiz.title,
                            detail: "\(quiz.questions.count) questions" + (quiz.bestScore.map { " · best \($0)/\(quiz.questions.count)" } ?? ""),
                            systemImage: "checklist",
                            tint: .green
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            workspace.deleteQuiz(quiz.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func savedRow(_ title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glowCard(tint, isActive: false)
    }

    private func progressCard(_ stage: String) -> some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(stage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: Actions

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, ai.isReady else { return }
        question = ""
        path.append(.chat(text))
    }

    /// The chosen notes as text for the AI, or `nil` (with a message) when there is none.
    private func notesText(for client: AIClient) async -> String? {
        stage = "Reading your notes…"
        let found = await NoteTexts.sources(sources, store: store, live: liveContent) { stage = $0 }
        guard !found.isEmpty else {
            stage = nil
            message = "There's no writing in these notes to study yet."
            return nil
        }
        return NoteTexts.context(found, budget: client.kind.contextBudget)
    }

    private func makeFlashcards() {
        guard let client = ai.client() else { return }
        Task {
            guard let notes = await notesText(for: client) else { return }
            stage = "Writing flashcards…"
            do {
                let reply = try await client.complete(
                    system: "You write excellent study flashcards.",
                    messages: [AIMessage(.user, StudyAI.flashcardsPrompt(notes: notes, count: 20))]
                )
                let cards = try StudyAI.flashcards(from: reply)
                let now = Date()
                let deck = FlashcardDeck(
                    id: UUID(),
                    title: scopeTitle,
                    sourceNoteIDs: sources,
                    cards: cards,
                    createdAt: now,
                    modifiedAt: now
                )
                workspace.save(deck)
                stage = nil
                path.append(.review(deck.id))
            } catch {
                stage = nil
                message = "Couldn't make flashcards: \(error.localizedDescription)"
            }
        }
    }

    private func makeQuiz() {
        guard let client = ai.client() else { return }
        Task {
            guard let notes = await notesText(for: client) else { return }
            stage = "Writing a quiz…"
            do {
                let reply = try await client.complete(
                    system: "You write fair, clear multiple-choice quizzes.",
                    messages: [AIMessage(.user, StudyAI.quizPrompt(notes: notes, count: 10))]
                )
                let quiz = Quiz(
                    id: UUID(),
                    title: scopeTitle,
                    sourceNoteIDs: sources,
                    questions: try StudyAI.quizQuestions(from: reply),
                    bestScore: nil,
                    createdAt: Date()
                )
                workspace.save(quiz)
                stage = nil
                path.append(.quiz(quiz.id))
            } catch {
                stage = nil
                message = "Couldn't make a quiz: \(error.localizedDescription)"
            }
        }
    }

    /// Organized study notes, saved as a text note in "Smart Notes".
    private func makeSmartNotes() {
        guard let client = ai.client() else { return }
        Task {
            guard let notes = await notesText(for: client) else { return }
            stage = "Writing smart notes…"
            do {
                var markdown = try await client.complete(
                    system: "You turn messy notes into clear study notes.",
                    messages: [AIMessage(.user, StudyAI.summaryPrompt(notes: notes))]
                )
                let links = sources.compactMap { store.note($0)?.title }.map { "[[\($0)]]" }
                if !links.isEmpty {
                    markdown += "\n\n---\nFrom " + links.joined(separator: ", ") + " #smartnotes"
                }
                let folder = store.folders.first(where: { $0.parentID == nil && $0.name == "Smart Notes" })
                    ?? store.createFolder(named: "Smart Notes")
                let note = store.createTextNote(titled: "Smart Notes: \(scopeTitle)", in: folder?.id)
                stage = nil
                if let note {
                    store.saveMarkdown(markdown, for: note.id)
                    createdNoteID = note.id
                    message = "\"\(note.title)\" is in the Smart Notes folder."
                }
            } catch {
                stage = nil
                message = "Couldn't write smart notes: \(error.localizedDescription)"
            }
        }
    }
}
