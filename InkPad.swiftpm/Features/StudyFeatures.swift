import Foundation
import PencilKit
import UserNotifications

/// Fills `{}` before looking the message up in the Arabic table.
private func trStudy(_ pattern: String, _ values: String...) -> String {
    var text = pattern
    for value in values { text = text.replacingOccurrences(of: "{}", with: value) }
    return trMessage(text)
}

// MARK: - Settings additions

extension InsightSettings {
    var simpleMode: Bool {
        get { _simpleMode }
        set { _simpleMode = newValue }
    }
}

// The stored fields live in the struct itself; these helpers keep the new
// features readable at their call sites.
extension InsightSettings {
    /// Whether the daily review reminder is allowed.
    var reviewReminders: Bool {
        get { reviewRemindersOn }
        set { reviewRemindersOn = newValue }
    }
}

// MARK: - Blank-Page Recall

/// Compares what a student wrote from memory with the source page. Only
/// single words are compared, using the same normalizer as handwriting
/// search, so spelling differences in Arabic and English do not matter.
enum RecallEngine {
    struct Result: Identifiable {
        let id = UUID()
        let captured: String
        let missed: [String]
        let sourceCount: Int
        let createdAt: Date
    }

    static func evaluate(source: String, written: String) -> Result {
        let sourceWords = Set(BookIndex.words(in: source))
        let writtenWords = Set(BookIndex.words(in: written))
        let missed = Array(sourceWords.subtracting(writtenWords)).sorted().prefix(16)
        return Result(
            captured: written,
            missed: Array(missed),
            sourceCount: sourceWords.count,
            createdAt: Date()
        )
    }

    static func recallScore(_ result: Result) -> Double {
        guard result.sourceCount > 0 else { return 0 }
        return Double(result.sourceCount - result.missed.count) / Double(result.sourceCount)
    }
}

// MARK: - Quick Capture

/// Where a one-tap capture lands: the daily note, without a title decision.
enum QuickCapture {
    @MainActor static func append(_ text: String, to noteID: UUID, store: LibraryStore) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let existing = (try? store.loadMarkdown(for: noteID)) ?? ""
        let stamp = Date().formatted(date: .omitted, time: .shortened)
        let addition = "\n\n— \(stamp)\n\(trimmed)\n"
        let updated = existing.isEmpty ? trimmed : existing + addition
        return store.saveMarkdown(updated, for: noteID)
    }

    @MainActor static func dailyNote(in store: LibraryStore) -> NoteSummary? {
        store.dailyNote(for: Date(), tasks: [])
    }
}

// MARK: - Review notifications

extension FlowNotifications {
    private static var reviewIdentifier: String { "InkPad.Reviews.Due" }
    private static var reviewCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    static func scheduleDailyReview(hour: Int) async {
        guard !isPlaygrounds else { return }
        await requestPermissionIfNeeded()
        let settings = await reviewCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        var date = DateComponents()
        date.hour = min(max(hour, 0), 23)
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = tr("Time to Review")
        content.body = tr("Your flashcards and margin questions are waiting in InkPad.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: reviewIdentifier, content: content, trigger: trigger)
        try? await reviewCenter.add(request)
    }

    static func cancelDailyReview() {
        guard !isPlaygrounds else { return }
        reviewCenter.removePendingNotificationRequests(withIdentifiers: [reviewIdentifier])
    }
}

// MARK: - Active-recall activities

enum ActivityKind: String, CaseIterable, Identifiable {
    case fillBlank, order, explain, label

    var id: Self { self }

    var title: String {
        switch self {
        case .fillBlank: "Fill the Blank"
        case .order: "Put in Order"
        case .explain: "Explain Simply"
        case .label: "Label the Idea"
        }
    }

    var symbol: String {
        switch self {
        case .fillBlank: "text.badge.asterisk"
        case .order: "arrow.up.arrow.down"
        case .explain: "bubble.left.and.text.bubble.right"
        case .label: "tag"
        }
    }
}

struct RecallActivity: Identifiable {
    let id = UUID()
    let kind: ActivityKind
    let prompt: String
    let answer: String
    var choices: [String] = []
}

/// Offline activity generator: it uses only the note's own words, so it
/// works with no AI service and never needs the Firewall.
enum ActivityEngine {
    static func make(_ kind: ActivityKind, from text: String) -> [RecallActivity] {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".\n!?。؟"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 5 }
        guard !sentences.isEmpty else { return [] }
        switch kind {
        case .fillBlank:
            return sentences.prefix(6).compactMap { sentence in
                let words = sentence.split(separator: " ").map(String.init)
                guard words.count > 2 else { return nil }
                var index = 1
                for position in 2..<(words.count - 1) where words[position].count > words[index].count { index = position }
                let hidden = words[index]
                var filled = words
                filled[index] = "_____"
                return RecallActivity(kind: kind, prompt: filled.joined(separator: " "), answer: hidden)
            }
        case .order:
            return sentences.prefix(4).compactMap { sentence in
                let parts = sentence.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 3 else { return nil }
                return RecallActivity(
                    kind: kind, prompt: tr("Put these in order:"),
                    answer: parts.joined(separator: " → "), choices: parts.shuffled()
                )
            }
        case .explain:
            return sentences.prefix(5).map { sentence in
                RecallActivity(
                    kind: kind,
                    prompt: trStudy("Explain this to a beginner, then reveal the note's own words: {}", String(sentence.prefix(120))),
                    answer: sentence
                )
            }
        case .label:
            return sentences.prefix(6).compactMap { sentence in
                let words = sentence.split(separator: " ").map(String.init)
                guard let term = words.max(by: { $0.count < $1.count }), term.count >= 5 else { return nil }
                return RecallActivity(kind: kind, prompt: trStudy("Which idea does this describe? {}", sentence), answer: term)
            }
        }
    }
}

// MARK: - Prerequisites in Knowledge GPS

extension KnowledgeStation {
    /// Stations that should be understood before this one.
    var prerequisiteIDs: [UUID] {
        get { prerequisiteList ?? [] }
        set { prerequisiteList = newValue }
    }
}

extension KnowledgeMap {
    /// Stations whose prerequisites are weak, with the reason.
    @MainActor func foundationWarnings(workspace: WorkspaceStore) -> [(station: KnowledgeStation, blocker: String)] {
        var warnings: [(KnowledgeStation, String)] = []
        for station in stations {
            for id in station.prerequisiteIDs {
                guard let required = stations.first(where: { $0.id == id }) else { continue }
                let memory = workspace.flashcardDecks
                    .flatMap(\.cards)
                    .filter { card in
                        required.title.isEmpty == false &&
                        (card.front.localizedCaseInsensitiveContains(required.title) || card.back.localizedCaseInsensitiveContains(required.title))
                    }
                    .compactMap { $0.recall() }
                if let weakest = memory.min(), weakest < 0.5 {
                    warnings.append((station, trStudy("Weak foundation: {}", required.title)))
                    break
                }
            }
        }
        return warnings
    }
}

// MARK: - Lecture study pack

struct LecturePack {
    var summary: String
    var cards: [Flashcard]
    var questions: [QuizQuestion]
}

enum LecturePackEngine {
    static func build(text: String, client: AIClient) async throws -> LecturePack {
        let excerpt = String(text.prefix(12_000))
        async let summaryReply = client.complete(
            system: "You write clear lecture notes. Keep the original language.",
            messages: [AIMessage(.user, "Summarize this lecture into short notes with headings and bullets.\n\n" + excerpt)]
        )
        async let cardsReply = client.complete(
            system: "You write study flashcards.",
            messages: [AIMessage(.user, StudyAI.flashcardsPrompt(notes: excerpt, count: 10))]
        )
        async let quizReply = client.complete(
            system: "You write exam questions.",
            messages: [AIMessage(.user, StudyAI.quizPrompt(notes: excerpt, count: 5))]
        )
        let summary = try await summaryReply
        let cards = try StudyAI.flashcards(from: await cardsReply)
        let questions = try StudyAI.quizQuestions(from: await quizReply)
        return LecturePack(summary: summary, cards: cards, questions: questions)
    }
}

// MARK: - Power search

/// Parses `tag:`, `folder:`, `kind:`, `hasaudio:` and `before:` operators.
/// Plain words stay in `text`, so normal search is unchanged.
struct SearchQuery {
    var text = ""
    var tags: [String] = []
    var folder = ""
    var kind = ""
    var hasAudio: Bool?
    var before: Date?

    static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery()
        var words: [String] = []
        var quote: String?
        var current = ""
        for character in raw + " " {
            if quote != nil {
                if character == "\"" {
                    if !current.isEmpty { words.append(current) }
                    current = ""
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" {
                if !current.isEmpty { words.append(current); current = "" }
                quote = ""
                continue
            }
            if character == " " {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            current.append(character)
        }
        for token in words {
            let lower = token.lowercased()
            if lower.hasPrefix("tag:"), token.count > 4 {
                query.tags.append(String(token.dropFirst(4)))
            } else if lower.hasPrefix("folder:"), token.count > 7 {
                query.folder = String(token.dropFirst(7))
            } else if lower.hasPrefix("kind:"), token.count > 5 {
                query.kind = String(token.dropFirst(5))
            } else if lower == "hasaudio:" || lower == "hasaudio" {
                query.hasAudio = true
            } else if lower.hasPrefix("before:"), token.count > 7 {
                let value = String(token.dropFirst(7))
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                query.before = formatter.date(from: value)
            } else {
                query.text.append(token)
                query.text.append(" ")
            }
        }
        query.text = query.text.trimmingCharacters(in: .whitespaces)
        return query
    }

    var isEmpty: Bool {
        text.isEmpty && tags.isEmpty && folder.isEmpty && kind.isEmpty && hasAudio == nil && before == nil
    }
}

// MARK: - Saved graph views

struct GraphViewPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var positions: [String: CGPoint]
    var pinned: [String]

    init(name: String, positions: [String: CGPoint], pinned: [String]) {
        id = UUID()
        self.name = name
        self.positions = positions
        self.pinned = pinned
    }
}

enum GraphViewStore {
    static let key = "graphSavedViews"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load() -> [GraphViewPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? decoder.decode([GraphViewPreset].self, from: data)
        else { return [] }
        return saved
    }

    static func save(_ presets: [GraphViewPreset]) {
        guard let data = try? encoder.encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
