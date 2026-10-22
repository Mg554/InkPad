import SwiftUI

/// Choose the AI service for studying and slides, and enter its API key.
struct AISettingsView: View {
    @ObservedObject private var ai = AISettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var keyText = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $ai.provider) {
                        ForEach(AIProviderKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                } footer: {
                    Text(ai.provider == .apple
                        ? "Runs on this iPad and needs no key (iPadOS 26 with Apple Intelligence turned on)."
                        : "Use your own account with this service. Notes you study are sent to it; nothing is sent anywhere else.")
                }

                if ai.provider.needsKey {
                    Section {
                        SecureField("Paste your API key", text: $keyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { ai.setKey(keyText, for: ai.provider) }
                            .onChange(of: keyText) { ai.setKey(keyText, for: ai.provider) }
                        if let page = ai.provider.keyPage {
                            Button {
                                openURL(page)
                            } label: {
                                Label("Get a Key", systemImage: "key")
                            }
                        }
                    } header: {
                        Text("API Key")
                    } footer: {
                        Text("Kept in this iPad's keychain.")
                    }

                    Section {
                        TextField(ai.provider.defaultModel.isEmpty ? "Model name" : ai.provider.defaultModel, text: $ai.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if ai.provider == .custom {
                            TextField("https://example.com/v1", text: $ai.customBaseURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                        Text(ai.provider == .custom ? "Model and Address" : "Model")
                    } footer: {
                        Text(ai.provider == .custom
                            ? "Any service with an OpenAI-compatible Chat Completions API, such as LM Studio or Together."
                            : "Leave it as it is, or type any model the service offers.")
                    }
                }

                Section {
                    Button {
                        test()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting || !ai.isReady)
                    if let problem = ai.problem {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    } else if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { keyText = ai.key(for: ai.provider) }
            .onChange(of: ai.provider) {
                keyText = ai.key(for: ai.provider)
                testResult = nil
            }
        }
    }

    private func test() {
        guard let client = ai.client() else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                let reply = try await client.complete(
                    system: "Answer in one short sentence.",
                    messages: [AIMessage(.user, "Say hello to an InkPad user.")]
                )
                testResult = "✓ Connected. \(reply)"
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
