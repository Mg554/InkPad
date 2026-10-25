import SwiftUI

/// "Chat with your notes": answers stream in as they are written, drawing on
/// the chosen notes (or all of them). Each conversation is saved with its
/// notes, so it can be read and continued later.
struct StudyChatView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @ObservedObject private var ai = AISettings.shared

    let sources: [UUID]
    let liveContent: [UUID: NoteContent]
    let firstQuestion: String

    /// The saved conversation; `nil` until the first question.
    @State private var chatID: UUID?
    @State private var messages: [AIMessage] = []
    @State private var input = ""
    @State private var isAnswering = false
    @State private var notes: String?
    @State private var stage: String?
    @State private var answerTask: Task<Void, Never>?

    init(sources: [UUID], liveContent: [UUID: NoteContent], firstQuestion: String = "", chatID: UUID? = nil) {
        self.sources = sources
        self.liveContent = liveContent
        self.firstQuestion = firstQuestion
        _chatID = State(initialValue: chatID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if let stage {
                        Label(stage, systemImage: "doc.text.magnifyingglass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: messages.last?.text) {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle("Chat with Your Notes")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.openURL, OpenURLAction { InkPadLink.handle($0, with: navigation) })
        .onAppear {
            if let chatID, messages.isEmpty,
               let chat = workspace.studyChats.first(where: { $0.id == chatID }) {
                messages = chat.messages
            } else if messages.isEmpty, !firstQuestion.isEmpty {
                send(firstQuestion)
            }
        }
        .onDisappear { answerTask?.cancel() }
    }

    @ViewBuilder
    private func bubble(_ message: AIMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .padding(.top, 4)
                if message.text.isEmpty {
                    ProgressView()
                        .padding(.top, 2)
                } else {
                    MarkdownPreview(text: message.text) { _ in }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glowCard(.purple, isActive: false)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a follow-up", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .onSubmit { send(input) }
            if isAnswering {
                Button {
                    answerTask?.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                }
                .accessibilityLabel("Stop")
            } else {
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .frame(maxWidth: 820)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        guard let client = ai.client() else {
            messages.append(AIMessage(.assistant, ai.problem ?? "Connect an AI service in AI Settings."))
            return
        }
        input = ""
        messages.append(AIMessage(.user, question))
        isAnswering = true
        answerTask = Task {
            if notes == nil {
                let found = await NoteTexts.sources(sources, store: store, live: liveContent) { stage = $0 }
                notes = NoteTexts.context(found, budget: client.kind.contextBudget, question: question)
                stage = nil
            }
            let history = messages
            messages.append(AIMessage(.assistant, ""))
            let index = messages.count - 1
            do {
                for try await piece in client.stream(system: StudyAI.chatSystem(notes: notes ?? ""), messages: history) {
                    messages[index].text += piece
                }
            } catch {
                // Stopping (cancelling) is not an error worth showing.
                if !Task.isCancelled {
                    let separator = messages[index].text.isEmpty ? "" : "\n\n"
                    messages[index].text += separator + "⚠️ " + error.localizedDescription
                }
            }
            if messages[index].text.isEmpty {
                messages[index].text = "(Stopped.)"
            }
            isAnswering = false
            saveChat()
        }
    }

    /// Keeps the conversation with its notes.
    private func saveChat() {
        guard let question = messages.first(where: { $0.role == .user })?.text else { return }
        let now = Date()
        let existing = chatID.flatMap { id in workspace.studyChats.first(where: { $0.id == id }) }
        let id = chatID ?? UUID()
        chatID = id
        workspace.save(StudyChat(
            id: id,
            title: existing?.title ?? String(question.prefix(80)),
            sourceNoteIDs: sources,
            messages: messages,
            createdAt: existing?.createdAt ?? now,
            modifiedAt: now
        ))
    }
}
