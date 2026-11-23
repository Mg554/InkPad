import SwiftUI

/// Connect an AI provider in three short steps: choose how, paste one key,
/// then test. The old screen asked for a provider, key, model, address and a
/// separate test all at once.
struct AISettingsView: View {
    @ObservedObject private var ai = AISettings.shared
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var step = 0
    @State private var keyText = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var keySaveTask: Task<Void, Never>?
    @State private var showAdvanced = false
    @State private var modelPickerTask: AITask?
    @State private var modelSearch = ""
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false

    private var hiddenCountText: String {
        let count = store.notes.filter { store.aiAccess(of: $0.id) != .allowed }.count
        switch count {
        case 0: return "Off"
        case 1: return "1 note protected"
        default: return "\(count) notes protected"
        }
    }

    private var title: String {
        switch step {
        case 0: "Connect AI"
        case 1: "Add Your Key"
        default: "Test and Finish"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    chooseScreen
                } else if step == 1 {
                    keyScreen
                } else {
                    connectScreen
                }
            }
            .navigationTitle(tr(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                keyText = ai.key(for: ai.provider)
                // Coming back to a working setup shows status, not the wizard.
                if ai.provider != .anthropic || !keyText.isEmpty { step = 2 }
                retestIfStale()
            }
            .onChange(of: ai.provider) { _, newProvider in
                keySaveTask?.cancel()
                keyText = ai.key(for: newProvider)
                testResult = nil
            }
            .onDisappear {
                keySaveTask?.cancel()
                ai.setKey(keyText, for: ai.provider)
            }
            .onChange(of: keyText) { _, newKey in
                keySaveTask?.cancel()
                let provider = ai.provider
                keySaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    ai.setKey(newKey, for: provider)
                }
            }
            .sheet(item: $modelPickerTask) { task in modelPicker(task) }
        }
    }

    // MARK: Step 1 — choose

    private var chooseScreen: some View {
        Form {
            Section {
                providerCard(
                    .apple,
                    subtitle: "No key. Notes stay on this iPad.",
                    badge: "Free · Private",
                    symbol: "ipad"
                ) {
                    ai.provider = .apple
                    step = 2
                }
            } header: {
                Text("On This iPad")
            }

            Section {
                providerCard(
                    .openRouter,
                    subtitle: "One key for Claude, Gemini, GPT and more.",
                    badge: "Recommended",
                    symbol: "sparkles"
                ) {
                    ai.provider = .openRouter
                    step = 1
                }
            } header: {
                Text("One Key, Many Models")
            } footer: {
                Text("OpenRouter is the easiest start: one account and one key, then switch models for each job below.")
            }

            Section {
                ForEach([AIProviderKind.anthropic, .openAI, .gemini, .groq, .deepSeek, .mistral]) { kind in
                    providerCard(kind, subtitle: blurb(kind), badge: "", symbol: "key") {
                        ai.provider = kind
                        step = 1
                    }
                }
            } header: {
                Text("Direct Accounts")
            }

            Section {
                providerCard(
                    .custom,
                    subtitle: "Your own OpenAI-compatible server or local model.",
                    badge: "Advanced",
                    symbol: "server.rack"
                ) {
                    ai.provider = .custom
                    step = 1
                }
            }
        }
    }

    private func providerCard(
        _ kind: AIProviderKind,
        subtitle: String,
        badge: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.inkAccent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tr(kind.title))
                            .foregroundStyle(Color.primary)
                        if !badge.isEmpty {
                            Text(tr(badge))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.inkAccent.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(tr(subtitle)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func blurb(_ kind: AIProviderKind) -> String {
        switch kind {
        case .anthropic: "Claude models, strong at writing."
        case .openAI: "ChatGPT models."
        case .gemini: "Google's Gemini models."
        case .groq: "Very fast open models."
        case .deepSeek: "Strong reasoning at low cost."
        case .mistral: "European models."
        case .openRouter, .apple, .custom: ""
        }
    }

    // MARK: Step 2 — key

    private var keyScreen: some View {
        Form {
            Section {
                if let page = ai.provider.keyPage {
                    Button {
                        openURL(page)
                    } label: {
                        Label("Get a Key", systemImage: "key")
                    }
                }
                SecureField("Paste your API key", text: $keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { saveKeyNow() }
            } header: {
                Text(ai.provider.title)
            } footer: {
                Text("The key is kept in this iPad's keychain. Notes are never stored by InkPad's AI setup.")
            }

            Section {
                Button("Continue") { saveKeyNow(); step = 2 }
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Model name", text: Binding(
                        get: { ai.model }, set: { ai.model = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    if ai.provider == .custom {
                        TextField("https://example.com/v1", text: $ai.customBaseURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            } footer: {
                Text("Most people leave this alone. The default model is filled in for you.")
            }
        }
    }

    private func saveKeyNow() {
        keySaveTask?.cancel()
        ai.setKey(keyText, for: ai.provider)
    }

    // MARK: Step 3 — test, models, health

    private var connectScreen: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: ai.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ai.isReady ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ai.isReady ? tr("Ready to use") : tr("Setup needed"))
                            .font(.subheadline.weight(.semibold))
                        Text(trMessage(statusText())).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    test()
                } label: {
                    HStack {
                        Label("Test and Connect", systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if isTesting { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isTesting || !ai.isReady)
                if let result = testResult {
                    Text(trMessage(result))
                        .font(.footnote)
                        .foregroundStyle(result.hasPrefix("✓") ? Color.green : Color.orange)
                }
            } header: {
                Text("Connection")
            }

            if ai.provider.needsKey {
                Section {
                    ForEach(AITask.allCases) { task in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(tr(task.title), systemImage: task.symbol)
                                .font(.subheadline)
                            TextField(ai.model, text: Binding(
                                get: { ai.model(for: task) },
                                set: { ai.setModel($0, for: task) }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)
                            .textFieldStyle(.roundedBorder)
                            Button("Choose from list…") {
                                modelSearch = ""
                                availableModels = []
                                modelPickerTask = task
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("Model for Each Job")
                } footer: {
                    Text("Leave a job empty to use the main model. Fast models are good for search; stronger ones for slides and study.")
                }
            }

            Section {
                NavigationLink {
                    AIFirewallView()
                } label: {
                    HStack {
                        Label("AI Firewall", systemImage: "lock.shield")
                        Spacer()
                        Text(trMessage(hiddenCountText)).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Choose notes and folders that are never sent to AI. The shield also shows on each AI sheet.")
            }
        }
    }

    private func statusText() -> String {
        let (date, ok) = ai.testStatus(for: ai.provider)
        guard let date else { return "Not tested yet." }
        if ok == false {
            return "Last test failed \(date.formatted(.relative(presentation: .named)))."
        }
        return "Last connected \(date.formatted(.relative(presentation: .named)))."
    }

    private func test() {
        guard let client = ai.client() else { return }
        isTesting = true
        testResult = nil
        let provider = ai.provider
        Task {
            do {
                let reply = try await client.complete(
                    system: "Answer in one short sentence.",
                    messages: [AIMessage(.user, "Say hello to an InkPad user.")]
                )
                ai.recordTest(for: provider, ok: true)
                testResult = "✓ Connected. \(reply)"
            } catch {
                ai.recordTest(for: provider, ok: false)
                testResult = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    /// Quietly retests a provider that was working more than a day ago.
    private func retestIfStale() {
        guard ai.isReady, let client = ai.client() else { return }
        let (date, ok) = ai.testStatus(for: ai.provider)
        guard let date, ok == true else { return }
        guard Date().timeIntervalSince(date) > 86_400 else { return }
        let provider = ai.provider
        Task {
            do {
                _ = try await client.complete(
                    system: "Answer with one word.",
                    messages: [AIMessage(.user, "Ping")]
                )
                ai.recordTest(for: provider, ok: true)
            } catch {
                ai.recordTest(for: provider, ok: false)
            }
        }
    }

    // MARK: Model picker

    private func modelPicker(_ task: AITask) -> some View {
        NavigationStack {
            Group {
                if isLoadingModels {
                    ProgressView(tr("Loading models…"))
                } else if availableModels.isEmpty {
                    ContentUnavailableView(
                        "No Model List",
                        systemImage: "server.rack",
                        description: Text("This service does not publish a model list. Type the model name above instead.")
                    )
                } else {
                    List(filteredModels, id: \.self) { name in
                        Button {
                            ai.setModel(name, for: task)
                            modelPickerTask = nil
                        } label: {
                            Text(verbatim: name).foregroundStyle(Color.primary)
                        }
                    }
                }
            }
            .navigationTitle(tr(task.title))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $modelSearch, prompt: "Find a model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { modelPickerTask = nil }
                }
            }
            .task {
                guard availableModels.isEmpty else { return }
                isLoadingModels = true
                let names = await ai.client()?.availableModels() ?? []
                availableModels = names
                isLoadingModels = false
            }
        }
    }

    private var filteredModels: [String] {
        let needle = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return availableModels }
        return availableModels.filter { $0.localizedCaseInsensitiveContains(needle) }
    }
}
