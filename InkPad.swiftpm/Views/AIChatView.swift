import SwiftUI

/// A general chat with an AI service — not about any note: the owner asks
/// anything, and picks the service that answers (Claude, ChatGPT, Gemini,
/// Groq, OpenRouter, DeepSeek, Mistral, Apple Intelligence or their own).
/// Conversations are kept with the workspace, so they can be read and
/// continued later.
struct AIChatView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var ai = AISettings.shared

    @State private var chatID: UUID?
    @State private var messages: [AIMessage] = []
    @State private var input = ""
    @State private var isAnswering = false
    @State private var answerTask: Task<Void, Never>?
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
        }
        .themedBackground()
        .navigationTitle("AI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSettings) {
            AISettingsView()
        }
        .onDisappear { answerTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(AIProviderKind.allCases) { provider in
                    Button {
                        ai.provider = provider
                    } label: {
                        if ai.provider == provider {
                            Label(provider.title, systemImage: "checkmark")
                        } else {
                            Text(provider.title)
                        }
                    }
                }
            } label: {
                Label(ai.provider.title, systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
            }
            .disabled(isAnswering)

            Text(ai.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Menu {
                Button {
                    newChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                if !workspace.recentAIChats.isEmpty {
                    Section("Saved Chats") {
                        ForEach(workspace.recentAIChats) { chat in
                            Button {
                                open(chat)
                            } label: {
                                Text(chat.title)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        welcome
                    }
                    ForEach(messages) { message in
                        bubble(message).id(message.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: messages.last?.text) {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask anything", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text("This chat is not about your notes. Choose the service that answers — Claude, ChatGPT, Gemini, Groq and the rest — and ask whatever you like.")
                .font(.body)
                .foregroundStyle(.secondary)
            if let problem = ai.problem {
                VStack(alignment: .leading, spacing: 8) {
                    Text(trMessage(problem))
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Connect an AI Service", systemImage: "key")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .background(Color.inkAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .padding(.top, 4)
                if message.text.isEmpty {
                    ProgressView().padding(.top, 2)
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
            TextField("Ask anything", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .onSubmit { send(input) }
            if isAnswering {
                Button {
                    answerTask?.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .accessibilityLabel("Stop")
            } else {
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
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
        .frame(maxWidth: 860)
    }

    // MARK: Talking

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        guard let client = ai.client() else {
            messages.append(AIMessage(.assistant, ai.problem ?? "Connect an AI service in AI Settings."))
            showsSettings = true
            return
        }
        input = ""
        messages.append(AIMessage(.user, question))
        isAnswering = true
        let history = messages
        messages.append(AIMessage(.assistant, ""))
        let index = messages.count - 1
        let provider = ai.provider.rawValue
        answerTask = Task {
            do {
                for try await piece in client.stream(system: AIChat.system, messages: history) {
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
            saveChat(provider: provider)
        }
    }

    /// Keeps the conversation with the workspace.
    private func saveChat(provider: String) {
        guard let question = messages.first(where: { $0.role == .user })?.text else { return }
        let now = Date()
        let existing = chatID.flatMap { id in workspace.aiChats.first { $0.id == id } }
        let id = chatID ?? UUID()
        chatID = id
        workspace.save(AIChat(
            id: id,
            title: existing?.title ?? String(question.prefix(80)),
            provider: provider,
            messages: messages,
            createdAt: existing?.createdAt ?? now,
            modifiedAt: now
        ))
    }

    private func newChat() {
        answerTask?.cancel()
        isAnswering = false
        chatID = nil
        messages = []
    }

    private func open(_ chat: AIChat) {
        answerTask?.cancel()
        isAnswering = false
        chatID = chat.id
        messages = chat.messages
    }
}

extension AIChat {
    /// What the AI is told in a general chat: a helpful assistant, with no
    /// mention of notes.
    static let system = """
    You are a helpful assistant in the owner's study app. Answer clearly and \
    briefly, and use markdown when it helps. If you are unsure, say so.
    """
}
