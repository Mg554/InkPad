import AVFoundation
import Foundation

/// Cuts a recording into pieces (temporary .m4a files), for services that
/// only take so much audio at once.
enum AudioChunker {
    struct Piece: Sendable {
        let url: URL
        /// Seconds from the start of the whole recording.
        let start: TimeInterval
    }

    static func pieces(of url: URL, length: TimeInterval, duration: TimeInterval) async throws -> [Piece] {
        let asset = AVURLAsset(url: url)
        var total = duration
        if total <= 0 {
            let time = try await asset.load(.duration)
            total = CMTimeGetSeconds(time)
        }
        guard total > length + 5 else { return [Piece(url: url, start: 0)] }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pieces-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var result: [Piece] = []
        var start: TimeInterval = 0
        var index = 0
        while start < total {
            try Task.checkCancellation()
            let end: TimeInterval = min(start + length, total)
            let out = folder.appendingPathComponent("piece-\(index).m4a")
            try await export(asset, from: start, to: end, into: out)
            result.append(Piece(url: out, start: start))
            start = end
            index += 1
        }
        return result
    }

    /// Deletes pieces made by `pieces(of:)` (never the original recording).
    static func remove(_ pieces: [Piece]) {
        for piece in pieces where piece.url.path.contains("/pieces-") {
            try? FileManager.default.removeItem(at: piece.url.deletingLastPathComponent())
        }
    }

    private static func export(_ asset: AVURLAsset, from start: TimeInterval, to end: TimeInterval, into url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AITranscriberError.cannotCut
        }
        session.outputURL = url
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        let box = ExportBox(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                if box.session.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: box.session.error ?? AITranscriberError.cannotCut)
                }
            }
        }
    }
}

private final class ExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

enum AITranscriberError: LocalizedError {
    case noService
    case cannotCut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noService:
            tr("Add an OpenAI, Groq or Gemini key in AI Settings to transcribe with AI.")
        case .cannotCut:
            tr("The recording couldn't be read.")
        case let .failed(reason):
            trMessage("The AI couldn't transcribe the recording (\(reason)).")
        }
    }
}

/// Turns a recording into text with an AI service that hears audio:
/// Whisper on OpenAI, Groq or an OpenAI-compatible service, or Gemini.
/// Used only when the AI Firewall allows sending this note's audio.
struct AITranscriber: Sendable {
    enum Service: Sendable {
        case whisper(baseURL: String, model: String)
        case gemini
    }

    let kind: AIProviderKind
    let service: Service
    let key: String

    var title: String { kind.title }

    /// The service to use: the chosen AI if it can hear audio, otherwise
    /// any other service with a saved key that can.
    @MainActor
    static func available() -> AITranscriber? {
        let settings = AISettings.shared
        var order: [AIProviderKind] = [.openAI, .groq, .gemini]
        if [.openAI, .groq, .gemini, .custom].contains(settings.provider) {
            order.removeAll { $0 == settings.provider }
            order.insert(settings.provider, at: 0)
        }
        for kind in order {
            let key = settings.key(for: kind)
            guard !key.isEmpty else { continue }
            switch kind {
            case .openAI:
                return AITranscriber(kind: kind, service: .whisper(baseURL: kind.defaultBaseURL, model: "whisper-1"), key: key)
            case .groq:
                return AITranscriber(kind: kind, service: .whisper(baseURL: kind.defaultBaseURL, model: "whisper-large-v3-turbo"), key: key)
            case .gemini:
                return AITranscriber(kind: kind, service: .gemini, key: key)
            case .custom:
                guard kind == settings.provider, !settings.baseURL.isEmpty else { continue }
                return AITranscriber(kind: kind, service: .whisper(baseURL: settings.baseURL, model: "whisper-1"), key: key)
            default:
                continue
            }
        }
        return nil
    }

    /// The whole recording as phrases, sent in pieces of ten minutes.
    func transcribe(
        _ url: URL,
        language: String,
        duration: TimeInterval,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> [AudioTranscript.Phrase] {
        let pieces = try await AudioChunker.pieces(of: url, length: 600, duration: duration)
        defer { AudioChunker.remove(pieces) }
        var phrases: [AudioTranscript.Phrase] = []
        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            await progress(trMessage("\(title) is listening… part \(index + 1) of \(pieces.count)"))
            let data = try Data(contentsOf: piece.url)
            let found: [AudioTranscript.Phrase]
            switch service {
            case let .whisper(baseURL, model):
                found = try await whisper(data, baseURL: baseURL, model: model, language: language)
            case .gemini:
                found = try await gemini(data, language: language)
            }
            phrases += found.map { phrase in
                var moved = phrase
                moved.start += piece.start
                return moved
            }
        }
        guard !phrases.isEmpty else { throw TranscriberError.nothingHeard }
        return phrases
    }

    // MARK: Whisper (OpenAI-compatible /audio/transcriptions)

    private func whisper(_ audio: Data, baseURL: String, model: String, language: String) async throws -> [AudioTranscript.Phrase] {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: base + "/audio/transcriptions") else { throw AITranscriberError.noService }
        let boundary = "InkPad-" + UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "verbose_json")
        let code = String(language.prefix(2))
        if !code.isEmpty { field("language", code) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        let json = try await send(request)
        let segments = json["segments"] as? [[String: Any]] ?? []
        if segments.isEmpty, let text = json["text"] as? String, !text.isEmpty {
            return [AudioTranscript.Phrase(start: 0, duration: 0, text: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
        return segments.compactMap { segment in
            guard let text = (segment["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let start = (segment["start"] as? Double) ?? 0
            let end = (segment["end"] as? Double) ?? start
            return AudioTranscript.Phrase(start: start, duration: max(end - start, 0), text: text)
        }
    }

    // MARK: Gemini (audio in the request)

    private func gemini(_ audio: Data, language: String) async throws -> [AudioTranscript.Phrase] {
        let model = "gemini-2.5-flash"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AITranscriberError.noService
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let prompt = [
            "Transcribe this recording word for word in its own language (\(language)).",
            "Write one sentence per line, each starting with its time from the start as [mm:ss].",
            "Write nothing else.",
        ].joined(separator: " ")
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "audio/mp4", "data": audio.base64EncodedString()]],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(request)
        let candidates = json["candidates"] as? [[String: Any]] ?? []
        let content = candidates.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return Self.timedPhrases(text)
    }

    /// Lines like "[01:23] text" as phrases.
    static func timedPhrases(_ text: String) -> [AudioTranscript.Phrase] {
        var phrases: [AudioTranscript.Phrase] = []
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else {
                if !line.isEmpty, var last = phrases.popLast() {
                    last.text += " " + line
                    phrases.append(last)
                }
                continue
            }
            let stamp = line[line.index(after: line.startIndex)..<close]
            let numbers: [Double] = stamp.split(separator: ":").compactMap { Double($0) }
            var seconds: Double = 0
            for number in numbers { seconds = seconds * 60 + number }
            let words = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard !words.isEmpty else { continue }
            if var last = phrases.popLast() {
                last.duration = max(seconds - last.start, 0)
                phrases.append(last)
            }
            phrases.append(AudioTranscript.Phrase(start: seconds, duration: 0, text: words))
        }
        return phrases
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let error = json["error"] as? [String: Any]
            let message = (error?["message"] as? String) ?? "HTTP \(status)"
            throw AITranscriberError.failed(message)
        }
        return json
    }
}
