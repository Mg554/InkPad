import SwiftUI

/// What Write → Think → Build makes from a lasso selection.
enum ThinkMode: String, CaseIterable, Identifiable {
    case concepts, flashcards, questions, explain

    var id: Self { self }

    var title: String {
        switch self {
        case .concepts: "Concepts"
        case .flashcards: "Flashcards"
        case .questions: "Questions"
        case .explain: "Explain"
        }
    }

    var systemImage: String {
        switch self {
        case .concepts: "point.3.connected.trianglepath.dotted"
        case .flashcards: "rectangle.on.rectangle"
        case .questions: "questionmark.bubble"
        case .explain: "lightbulb"
        }
    }

    var tint: Color {
        switch self {
        case .concepts: .indigo
        case .flashcards: .orange
        case .questions: .teal
        case .explain: .purple
        }
    }
}

/// A lasso selection to think about.
struct ThinkRequest: Identifiable {
    let id = UUID()
    let text: String
}

/// Write → Think → Build: turns the writing circled with the lasso into
/// concepts, flashcards, questions or an explanation, and keeps the result
/// as a text note or a flashcard deck.
struct ThinkView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var ai = AISettings.shared
    @Environment(\.dismiss) private var dismiss

    let noteID: UUID
    @State private var passage: String
    @State private var mode: ThinkMode = .concepts
    @State private var isThinking = false
    @State private var result: String?
    @State private var cards: [Flashcard] = []
    @State private var error: String?
    @State private var savedMessage: String?
    @State private var isShowingSettings = false
    @State private var task: Task<Void, Never>?

    init(noteID: UUID, text: String) {
        self.noteID = noteID
        _passage = State(initialValue: text)
    }

    private var noteTitle: String { store.note(noteID)?.title ?? "Note" }
    private var isHidden: Bool { store.isHiddenFromAI(noteID) }
    private var hasPassage: Bool { !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isHidden {
                        notice(
                            "Protected by the AI Firewall",
                            "This note is never sent to AI. Turn off \"Hide from AI\" on the note or its folder to think about it.",
                            image: "lock.shield.fill",
                            tint: .green
                        )
                    } else if let problem = ai.problem {
                        notice("Connect an AI service", problem, image: "sparkles", tint: .purple) {
                            Button("Open AI Settings") { isShowingSettings = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    passageCard
                    modePicker
                    thinkButton
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    resultCard
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Think")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                AISettingsView()
            }
            .alert("Saved", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(savedMessage ?? "")
            }
        }
    }

    // MARK: Parts

    private var passageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What you wrote", systemImage: "pencil.and.scribble")
                .font(.headline)
            if hasPassage {
                Text("Read from your handwriting. Fix any word the iPad misread before thinking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No writing could be read in the selection. Type the words here, or circle clearer writing.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            TextEditor(text: $passage)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            ForEach(ThinkMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.title2)
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(mode == item ? Color.white : item.tint)
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .background(mode == item ? item.tint : item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(item.tint.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
    }

    private var thinkButton: some View {
        Button {
            think()
        } label: {
            HStack {
                if isThinking {
                    ProgressView().tint(.white)
                    Text("Thinking…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Make \(mode.title)")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .tint(mode.tint)
        .disabled(isThinking || isHidden || !ai.isReady || !hasPassage)
    }

    @ViewBuilder
    private var resultCard: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(cards.count) Flashcards")
                    .font(.title3.bold())
                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.front).font(.headline)
                        Text(card.back).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    saveCards()
                } label: {
                    Label("Add to Flashcards", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } else if let result {
            VStack(alignment: .leading, spacing: 12) {
                MarkdownPreview(text: result) { _ in }
                HStack {
                    Button {
                        saveNote(result)
                    } label: {
                        Label("Save as Note", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        UIPasteboard.general.string = result
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(mode.tint.opacity(0.3)))
        }
    }

    private func notice(
        _ title: String,
        _ message: String,
        image: String,
        tint: Color,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glowCard(tint)
    }

    // MARK: Actions

    private func think() {
        // Checked again here: the AI Firewall is never bypassed.
        guard !isHidden, hasPassage, let client = ai.client() else { return }
        let chosen = mode
        let prompt = StudyAI.thinkPrompt(chosen, passage: passage, noteTitle: noteTitle)
        isThinking = true
        error = nil
        result = nil
        cards = []
        task = Task {
            defer { isThinking = false }
            do {
                let reply = try await client.complete(
                    system: "You help a student think deeply about their own handwritten notes.",
                    messages: [AIMessage(.user, prompt)]
                )
                guard !Task.isCancelled else { return }
                if chosen == .flashcards {
                    cards = try StudyAI.flashcards(from: reply)
                } else {
                    result = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                if !Task.isCancelled {
                    self.error = "Couldn't think about this: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Kept in the "Thinking" folder, linked back to the note.
    private func saveNote(_ markdown: String) {
        let folder = store.folders.first(where: { $0.parentID == nil && $0.name == "Thinking" })
            ?? store.createFolder(named: "Thinking")
        guard let note = store.createTextNote(titled: "\(mode.title): \(noteTitle)", in: folder?.id) else { return }
        let body = [
            "# \(mode.title): \(noteTitle)",
            "",
            markdown,
            "",
            "---",
            "From [[\(noteTitle)]] #thinking",
        ].joined(separator: "\n")
        store.saveMarkdown(body, for: note.id)
        savedMessage = "\"\(note.title)\" is in the Thinking folder."
    }

    private func saveCards() {
        let now = Date()
        let deck = FlashcardDeck(
            id: UUID(),
            title: "\(noteTitle) (selection)",
            sourceNoteIDs: [noteID],
            cards: cards,
            createdAt: now,
            modifiedAt: now
        )
        workspace.save(deck)
        cards = []
        savedMessage = "The cards are in Study with AI, ready for review."
    }
}
