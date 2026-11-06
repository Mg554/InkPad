import Foundation

/// A question-and-answer card, reviewed with spaced repetition (Leitner
/// boxes: each correct answer moves it to a box reviewed less often).
struct Flashcard: Codable, Identifiable, Equatable {
    enum Rating: CaseIterable {
        case again, hard, good, easy

        var title: String {
            switch self {
            case .again: "Again"
            case .hard: "Hard"
            case .good: "Good"
            case .easy: "Easy"
            }
        }
    }

    /// Days until the next review, by box.
    static let intervals: [Double] = [0, 1, 3, 7, 16, 35, 90]

    let id: UUID
    var front: String
    var back: String
    var box: Int
    var due: Date
    /// When it was last reviewed (`nil` for cards from before this was kept).
    var lastReviewed: Date?

    init(front: String, back: String) {
        id = UUID()
        self.front = front
        self.back = back
        box = 0
        due = Date()
    }

    var isDue: Bool { due <= Date() }

    mutating func review(_ rating: Rating, now: Date = Date()) {
        lastReviewed = now
        switch rating {
        case .again:
            box = 0
            due = now.addingTimeInterval(60)
            return
        case .hard:
            box = max(box, 1)
        case .good:
            box = min(box + 1, Self.intervals.count - 1)
        case .easy:
            box = min(box + 2, Self.intervals.count - 1)
        }
        let days = Self.intervals[box] * (rating == .hard ? 0.5 : 1)
        due = now.addingTimeInterval(max(days, 0.5) * 86_400)
    }
}

extension Flashcard {
    /// The estimated chance of recalling the card now (0...1), from a
    /// forgetting curve that reaches 90% when the card falls due. `nil` for a
    /// card never studied; a card just forgotten counts as weak.
    func recall(now: Date = Date()) -> Double? {
        guard box > 0 else { return lastReviewed == nil ? nil : 0.2 }
        let interval = max(Self.intervals[box], 0.5) * 86_400
        let reviewed = lastReviewed ?? due.addingTimeInterval(-interval)
        let elapsed = max(0, now.timeIntervalSince(reviewed))
        return pow(0.9, elapsed / interval)
    }
}

struct FlashcardDeck: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var sourceNoteIDs: [UUID]
    var cards: [Flashcard]
    let createdAt: Date
    var modifiedAt: Date

    var dueCount: Int { cards.filter(\.isDue).count }

    /// Memory Heatmap: the average recall of the cards studied so far, or
    /// `nil` before any card was studied.
    func memoryStrength(now: Date = Date()) -> Double? {
        let recalls = cards.compactMap { $0.recall(now: now) }
        guard !recalls.isEmpty else { return nil }
        return recalls.reduce(0, +) / Double(recalls.count)
    }

    var studiedCount: Int { cards.filter { $0.recall() != nil }.count }
}

struct QuizQuestion: Codable, Identifiable, Equatable {
    let id: UUID
    var question: String
    var choices: [String]
    /// Index into `choices`.
    var answer: Int
    var explanation: String
}

struct Quiz: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var sourceNoteIDs: [UUID]
    var questions: [QuizQuestion]
    /// Most questions answered right in one go.
    var bestScore: Int?
    let createdAt: Date
}

/// A "Chat with your notes" conversation, kept so it can be read and
/// continued later. Belongs to the notes it was about (none: all notes).
struct StudyChat: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var sourceNoteIDs: [UUID]
    var messages: [AIMessage]
    let createdAt: Date
    var modifiedAt: Date

    /// Whether this chat was about exactly these notes.
    func isAbout(_ ids: [UUID]) -> Bool {
        Set(sourceNoteIDs) == Set(ids)
    }
}
