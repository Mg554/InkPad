import Foundation
import Speech

/// What was said in a recording, and its chapters (Voice → Timeline).
/// Stored next to the audio as `audio/<file>.transcript.json`; derived from
/// the recording, so it is safe to lose and can be made again.
struct AudioTranscript: Codable, Equatable {
    static let currentVersion = 1

    /// A short run of speech, about a sentence.
    struct Phrase: Codable, Equatable, Identifiable {
        var id: TimeInterval { start }
        /// Seconds from the start of the recording.
        var start: TimeInterval
        var duration: TimeInterval
        var text: String
    }

    struct Chapter: Codable, Equatable, Identifiable {
        var id: TimeInterval { start }
        var start: TimeInterval
        var title: String
    }

    var version = Self.currentVersion
    /// The language it was heard in (a locale identifier such as "ar-SA").
    var language: String
    var phrases: [Phrase]
    var chapters: [Chapter]
    /// Chapters written by an AI service rather than outlined on the iPad.
    var chaptersByAI: Bool

    var text: String { phrases.map(\.text).joined(separator: " ") }

    /// The chapter playing at `time`.
    func chapter(at time: TimeInterval) -> Chapter? {
        chapters.last { $0.start <= time + 0.5 }
    }

    /// Phrases containing `search`, for jumping to where a word was said.
    func phrases(matching search: String) -> [Phrase] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return phrases.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    /// Lines like "[01:23] text", for the AI.
    var timedLines: String {
        phrases.map { "[\(AudioClock.string($0.start))] \($0.text)" }.joined(separator: "\n")
    }
}

enum TranscriberError: LocalizedError {
    case notAllowed
    case unavailable(String)
    case nothingHeard
    case failed(language: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            "InkPad may not use speech recognition. Allow it in Settings › Privacy & Security › Speech Recognition."
        case let .unavailable(language):
            "Speech in \(language) can't be read on this iPad. Choose another language, or add it in Settings › General › Keyboard › Dictation Languages."
        case .nothingHeard:
            "No speech was heard in this recording."
        case let .failed(language, reason):
            "Speech in \(language) couldn't be read on this iPad (\(reason)). Make sure Dictation is on and \(language) is downloaded in Settings › General › Keyboard, then try again."
        }
    }
}

/// Turns recordings into text with Apple's speech recognition, always on
/// the iPad (`requiresOnDeviceRecognition`), so the audio never leaves it.
enum Transcriber {
    /// Languages offered for transcription: the iPad's own first, then
    /// common ones, keeping those the iPad can recognize by itself.
    static var languages: [Locale] {
        var identifiers = [Locale.current.identifier]
        identifiers += ["ar-SA", "en-US", "en-GB", "fr-FR", "de-DE", "es-ES", "tr-TR", "it-IT"]
        var seen: Set<String> = []
        return identifiers
            .map { Locale(identifier: $0) }
            .filter { locale in
                guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
                return recognizer.supportsOnDeviceRecognition && seen.insert(recognizer.locale.identifier).inserted
            }
    }

    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default:
            return false
        }
    }

    static func transcribe(_ url: URL, locale: Locale) async throws -> [AudioTranscript.Phrase] {
        guard await authorize() else { throw TranscriberError.notAllowed }
        let name = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw TranscriberError.unavailable(name)
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let box = TaskBox()
        let segments: [SFTranscriptionSegment]
        do {
            segments = try await recognize(request, with: recognizer, box: box)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriberError.failed(language: name, reason: error.localizedDescription)
        }
        let phrases = Self.phrases(from: segments)
        guard !phrases.isEmpty else { throw TranscriberError.nothingHeard }
        return phrases
    }

    private static func recognize(
        _ request: SFSpeechURLRecognitionRequest,
        with recognizer: SFSpeechRecognizer,
        box: TaskBox
    ) async throws -> [SFTranscriptionSegment] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var finished = false
                box.task = recognizer.recognitionTask(with: request) { result, error in
                    guard !finished else { return }
                    if let result, result.isFinal {
                        finished = true
                        continuation.resume(returning: result.bestTranscription.segments)
                    } else if let error {
                        finished = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// Joins recognized words into phrases: a new phrase after a pause,
    /// after a sentence ends, or once a phrase gets long.
    static func phrases(from segments: [SFTranscriptionSegment]) -> [AudioTranscript.Phrase] {
        var phrases: [AudioTranscript.Phrase] = []
        var words: [String] = []
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        func flush() {
            guard !words.isEmpty else { return }
            phrases.append(AudioTranscript.Phrase(start: start, duration: max(end - start, 0), text: words.joined(separator: " ")))
            words = []
        }
        for segment in segments {
            let word = segment.substring.trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            if !words.isEmpty, segment.timestamp - end > 1.2 || words.count >= 18 {
                flush()
            }
            if words.isEmpty { start = segment.timestamp }
            words.append(word)
            end = segment.timestamp + segment.duration
            if let last = word.last, ".?!؟".contains(last), words.count >= 4 {
                flush()
            }
        }
        flush()
        return phrases
    }

    /// Chapters made on the iPad without AI: a new chapter about every
    /// `duration / 8` (at least a minute), starting at a phrase, named after
    /// its first words.
    static func outlineChapters(_ phrases: [AudioTranscript.Phrase], duration: TimeInterval) -> [AudioTranscript.Chapter] {
        let step = max(60, duration / 8)
        var chapters: [AudioTranscript.Chapter] = []
        var next: TimeInterval = 0
        for phrase in phrases where phrase.start >= next {
            let words = phrase.text.split(separator: " ").prefix(6).joined(separator: " ")
            let title = phrase.text.split(separator: " ").count > 6 ? words + "…" : words
            chapters.append(AudioTranscript.Chapter(start: chapters.isEmpty ? 0 : phrase.start, title: title))
            next = phrase.start + step
        }
        return chapters
    }
}

/// Holds the running recognition task so cancelling can stop it.
private final class TaskBox: @unchecked Sendable {
    var task: SFSpeechRecognitionTask?
}
