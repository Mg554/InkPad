import Foundation
import Security

/// The AI services InkPad can study and write with. All but Apple
/// Intelligence run in the cloud with the user's own API key.
enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case anthropic, openAI, gemini, openRouter, groq, deepSeek, mistral, custom, apple

    enum Style {
        /// Anthropic's Messages API.
        case anthropic
        /// The OpenAI Chat Completions API, which most services also offer.
        case openAI
        /// Apple Intelligence on the iPad.
        case onDevice
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .anthropic: "Claude (Anthropic)"
        case .openAI: "ChatGPT (OpenAI)"
        case .gemini: "Gemini (Google)"
        case .openRouter: "OpenRouter"
        case .groq: "Groq"
        case .deepSeek: "DeepSeek"
        case .mistral: "Mistral"
        case .custom: "Other (OpenAI-compatible)"
        case .apple: "Apple Intelligence (on this iPad)"
        }
    }

    var style: Style {
        switch self {
        case .anthropic: .anthropic
        case .apple: .onDevice
        default: .openAI
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .mistral: "https://api.mistral.ai/v1"
        case .custom, .apple: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openAI: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        case .openRouter: "anthropic/claude-sonnet-5-5"
        case .groq: "llama-3.3-70b-versatile"
        case .deepSeek: "deepseek-chat"
        case .mistral: "mistral-medium-latest"
        case .custom, .apple: ""
        }
    }

    /// Where to create an API key.
    var keyPage: URL? {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: URL(string: "https://openrouter.ai/keys")
        case .groq: URL(string: "https://console.groq.com/keys")
        case .deepSeek: URL(string: "https://platform.deepseek.com/api_keys")
        case .mistral: URL(string: "https://console.mistral.ai/api-keys")
        case .custom, .apple: nil
        }
    }

    var needsKey: Bool { self != .apple }

    /// How much note text (in characters) to send at once.
    var contextBudget: Int {
        self == .apple ? 5000 : 120_000
    }
}

/// The chosen AI service, its model, and the user's API keys (kept in the
/// iPad's keychain). Shared by every screen.
@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()

    private struct Saved: Codable {
        var provider: AIProviderKind
        var models: [String: String]
        var customBaseURL: String?
    }

    private static let defaultsKey = "aiSettings"

    @Published var provider: AIProviderKind = .anthropic { didSet { save() } }
    @Published private var models: [String: String] = [:] { didSet { save() } }
    @Published var customBaseURL = "" { didSet { save() } }
    /// Bumped when a key changes, so views re-read `hasKey`.
    @Published private(set) var keyRevision = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            provider = saved.provider
            models = saved.models
            customBaseURL = saved.customBaseURL ?? ""
        }
    }

    var model: String {
        get { models[provider.rawValue] ?? provider.defaultModel }
        set { models[provider.rawValue] = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var baseURL: String {
        provider == .custom ? customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) : provider.defaultBaseURL
    }

    func key(for kind: AIProviderKind) -> String {
        _ = keyRevision
        return KeyStore.value(for: kind.rawValue) ?? ""
    }

    func setKey(_ key: String, for kind: AIProviderKind) {
        KeyStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: kind.rawValue)
        keyRevision += 1
    }

    /// `nil` when the chosen service can be used; otherwise what is missing.
    var problem: String? {
        switch provider.style {
        case .onDevice:
            return SlideWriterAI.unavailableReason
        case .anthropic, .openAI:
            if key(for: provider).isEmpty { return "Add your \(provider.title) API key in AI Settings." }
            if model.isEmpty { return "Choose a model in AI Settings." }
            if baseURL.isEmpty || URL(string: baseURL) == nil { return "Enter the service's address in AI Settings." }
            return nil
        }
    }

    var isReady: Bool { problem == nil }

    /// A client for the chosen service, or `nil` when it is not set up.
    func client() -> AIClient? {
        guard isReady else { return nil }
        return AIClient(kind: provider, baseURL: baseURL, model: model, key: key(for: provider))
    }

    /// A short description such as "Claude · claude-opus-5-5".
    var summary: String {
        provider == .apple ? provider.title : "\(provider.title) · \(model)"
    }

    private func save() {
        let saved = Saved(provider: provider, models: models, customBaseURL: customBaseURL)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// API keys in the keychain. If the keychain refuses (an app without
/// keychain access), keys fall back to the app's own settings.
enum KeyStore {
    private static let service = "InkPad.AI"

    static func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let text = String(data: data, encoding: .utf8) {
            return text
        }
        return UserDefaults.standard.string(forKey: fallbackKey(account))
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(account))
        guard !value.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(item as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(value, forKey: fallbackKey(account))
        }
    }

    private static func fallbackKey(_ account: String) -> String {
        "aiKey." + account
    }
}
