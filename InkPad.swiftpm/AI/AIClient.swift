import Foundation

/// One turn of a conversation with the AI.
struct AIMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant
    }

    let id: UUID
    var role: Role
    var text: String

    init(_ role: Role, _ text: String) {
        id = UUID()
        self.role = role
        self.text = text
    }
}

enum AIError: LocalizedError {
    case badAddress
    case http(status: Int, message: String)
    case refused
    case empty
    case unreadable

    var errorDescription: String? {
        switch self {
        case .badAddress: "The AI service's address isn't valid. Check AI Settings."
        case let .http(status, message):
            status == 401 || status == 403
                ? "The AI service didn't accept the API key (\(status)). Check it in AI Settings."
                : "The AI service answered with an error (\(status)): \(message)"
        case .refused: "The AI declined to answer this request."
        case .empty: "The AI sent back an empty answer. Try again."
        case .unreadable: "The AI's answer couldn't be read. Try again."
        }
    }
}

/// Talks to the chosen AI service: Anthropic's Messages API, any OpenAI
/// Chat Completions-compatible service, or Apple Intelligence on the iPad.
struct AIClient: Sendable {
    let kind: AIProviderKind
    let baseURL: String
    let model: String
    let key: String

    /// The whole answer at once.
    func complete(system: String, messages: [AIMessage]) async throws -> String {
        switch kind.style {
        case .onDevice:
            return try await OnDeviceModel.respond(to: Self.flattened(system: system, messages: messages))
        case .anthropic:
            let request = try anthropicRequest(system: system, messages: messages, stream: false)
            let json = try await send(request)
            if json["stop_reason"] as? String == "refusal" { throw AIError.refused }
            let blocks = json["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw AIError.empty }
            return text
        case .openAI:
            let request = try openAIRequest(system: system, messages: messages, stream: false)
            let json = try await send(request)
            let choices = json["choices"] as? [[String: Any]] ?? []
            let message = choices.first?["message"] as? [String: Any]
            guard let text = message?["content"] as? String, !text.isEmpty else { throw AIError.empty }
            return text
        }
    }

    /// The answer as it is written, piece by piece.
    func stream(system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamText(system: system, messages: messages) { piece in
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamText(system: String, messages: [AIMessage], yield: (String) -> Void) async throws {
        let request: URLRequest
        switch kind.style {
        case .onDevice:
            yield(try await complete(system: system, messages: messages))
            return
        case .anthropic:
            request = try anthropicRequest(system: system, messages: messages, stream: true)
        case .openAI:
            request = try openAIRequest(system: system, messages: messages, stream: true)
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 2000 { break }
            }
            throw AIError.http(status: status, message: Self.errorMessage(in: body))
        }
        var wroteSomething = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            if let error = json["error"] as? [String: Any] {
                throw AIError.http(status: status, message: error["message"] as? String ?? "Unknown error")
            }
            switch kind.style {
            case .anthropic:
                let delta = json["delta"] as? [String: Any]
                if json["type"] as? String == "content_block_delta",
                   delta?["type"] as? String == "text_delta",
                   let text = delta?["text"] as? String {
                    wroteSomething = true
                    yield(text)
                } else if json["type"] as? String == "message_delta", delta?["stop_reason"] as? String == "refusal" {
                    throw AIError.refused
                }
            case .openAI:
                let choices = json["choices"] as? [[String: Any]] ?? []
                if let delta = choices.first?["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
                    wroteSomething = true
                    yield(text)
                }
            case .onDevice:
                break
            }
        }
        if !wroteSomething { throw AIError.empty }
    }

    // MARK: Requests

    private func endpoint(_ path: String) throws -> URL {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + path), url.scheme == "https" || url.scheme == "http" else {
            throw AIError.badAddress
        }
        return url
    }

    private func anthropicRequest(system: String, messages: [AIMessage], stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: try endpoint("/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": stream ? 32000 : 16000,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            "stream": stream,
        ]
        // If a safety check declines on these models, the API retries on
        // another model instead of failing.
        if ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"].contains(model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func openAIRequest(system: String, messages: [AIMessage], stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: try endpoint("/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if kind == .openRouter {
            request.setValue("InkPad", forHTTPHeaderField: "X-Title")
        }
        let conversation: [[String: String]] = [["role": "system", "content": system]]
            + messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        let body: [String: Any] = [
            "model": model,
            "messages": conversation,
            "stream": stream,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AIError.http(status: status, message: Self.errorMessage(in: String(decoding: data, as: UTF8.self)))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AIError.unreadable
        }
        return json
    }

    private static func errorMessage(in body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        return String(body.prefix(300))
    }

    /// For the on-device model, which takes one prompt.
    private static func flattened(system: String, messages: [AIMessage]) -> String {
        var parts = [system]
        for message in messages {
            parts.append((message.role == .user ? "User: " : "Assistant: ") + message.text)
        }
        parts.append("Assistant:")
        return parts.joined(separator: "\n\n")
    }
}

/// Pulls the JSON object out of an AI answer, which may wrap it in prose or
/// a ``` code fence.
enum AIJSON {
    static func object(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let candidate = String(text[start...end])
        guard let data = candidate.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
