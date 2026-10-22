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

    init(front: String, back: String) {
        id = UUID()
        self.front = front
        self.back = back
        box = 0
        due = Date()
    }

    var isDue: Bool { due <= Date() }

    mutating func review(_ rating: Rating, now: Date = Date()) {
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

struct FlashcardDeck: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var sourceNoteIDs: [UUID]
    var cards: [Flashcard]
    let createdAt: Date
    var modifiedAt: Date

    var dueCount: Int { cards.filter(\.isDue).count }
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
