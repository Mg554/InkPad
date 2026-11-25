import Foundation

// MARK: - Socratic tutor

/// Guides the student with questions instead of revealing the answer.
enum SocraticPrompts {
    static let system = """
    You are a Socratic tutor studying a student's own notes. Never give the full answer at once. \
    Ask one short question at a time that leads the student to the answer. If they are stuck, give a small hint, \
    not the solution. Only when the student writes "reveal" or after they have answered twice, state the answer briefly. \
    Use the notes' language and cite note page labels when you use them.
    """

    static func system(context: String, title: String) -> String {
        system + "\n\nNote: \(title)\n\n\(context)"
    }
}

// MARK: - @references in Ask This Page

struct AskReferences {
    var cleanQuestion: String
    var pages: [Int] = []
    var noteTitles: [String] = []
    var concepts: [String] = []

    /// Reads `@page 4`, `@note Title` and `@concept Term`. Words after a
    /// token belong to it until the next `@` token, so Arabic titles work.
    static func parse(_ raw: String) -> AskReferences {
        var result = AskReferences(cleanQuestion: "")
        let tokens = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        func apply(_ kind: String, _ value: String) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if kind == "page" {
                if let number = Int(text) { result.pages.append(max(number - 1, 0)) }
            } else if kind == "note" {
                result.noteTitles.append(text)
            } else if kind == "concept" {
                result.concepts.append(text)
            }
        }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("@") {
                let body = String(token.dropFirst())
                let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
                let kind = parts.first?.lowercased() ?? ""
                if parts.count > 1 {
                    apply(kind, parts[1])
                    index += 1
                } else if kind == "page", index + 1 < tokens.count, let number = Int(tokens[index + 1]) {
                    result.pages.append(max(number - 1, 0))
                    index += 2
                } else {
                    index += 1
                    var words: [String] = []
                    while index < tokens.count, !tokens[index].hasPrefix("@") {
                        words.append(tokens[index])
                        index += 1
                    }
                    apply(kind, words.joined(separator: " "))
                }
                continue
            }
            if !result.cleanQuestion.isEmpty { result.cleanQuestion.append(" ") }
            result.cleanQuestion.append(token)
            index += 1
        }
        result.cleanQuestion = result.cleanQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

// MARK: - Interleaved review

enum InterleaveEngine {
    /// Round-robin across decks so two cards from the same deck never sit
    /// next to each other when other decks still have cards left.
    static func ordered(_ items: [(deckID: UUID, cardID: UUID)]) -> [(deckID: UUID, cardID: UUID)] {
        var buckets: [UUID: [(deckID: UUID, cardID: UUID)]] = [:]
        for item in items { buckets[item.deckID, default: []].append(item) }
        var keys = buckets.keys.shuffled()
        var result: [(deckID: UUID, cardID: UUID)] = []
        while !keys.isEmpty {
            var next: [UUID] = []
            for key in keys {
                if let card = buckets[key]?.popLast() {
                    result.append(card)
                    if !(buckets[key]?.isEmpty ?? true) { next.append(key) }
                }
            }
            keys = next
        }
        return result
    }
}

// MARK: - Flashcard quality

struct CardQuality: Identifiable {
    let id = UUID()
    let front: String
    let reason: String
}

enum FlashcardQuality {
    /// Finds cards that ask for a single forgotten word or give no context.
    static func issues(in decks: [FlashcardDeck]) -> [CardQuality] {
        var found: [CardQuality] = []
        for deck in decks {
            for card in deck.cards {
                let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
                if front.count < 8 {
                    found.append(CardQuality(front: front, reason: tr("Question is too short to stand alone.")))
                } else if answer.split(separator: " ").count <= 1 && answer.count < 12 {
                    found.append(CardQuality(front: front, reason: tr("Answer is one bare word; add a sentence of context.")))
                } else if front.lowercased().hasPrefix("what is ") && answer.count < 20 {
                    found.append(CardQuality(front: front, reason: tr("Definition card; add when and where it applies.")))
                }
            }
        }
        return Array(found.prefix(40))
    }
}

// MARK: - Learning efficiency

struct LearningMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

enum LearningStats {
    @MainActor static func report(workspace: WorkspaceStore) -> [LearningMetric] {
        let sessions = workspace.flowSessions
        let focusSeconds = sessions.reduce(0) { $0 + $1.workSeconds }
        let cards = workspace.flashcardDecks.flatMap(\.cards)
        let studied = cards.filter { $0.recall() != nil }
        let strong = studied.filter { ($0.recall() ?? 0) >= 0.8 }
        let hours = max(Double(focusSeconds) / 3600, 0.1)
        let perHour = Double(strong.count) / hours
        let due = cards.filter(\.isDue).count
        let quizzes = workspace.quizzes
        let best = quizzes.compactMap(\.bestScore)
        let averageQuiz = best.isEmpty ? 0 : best.reduce(0, +) / best.count
        let questionCount = quizzes.reduce(0) { $0 + $1.questions.count }
        var metrics: [LearningMetric] = [
            LearningMetric(title: tr("Focus time"), value: Flowmodoro.duration(focusSeconds),
                           detail: tr("Across all finished Flowmodoro sessions.")),
            LearningMetric(title: tr("Concepts remembered per hour"), value: String(format: "%.1f", perHour),
                           detail: tr("Cards with at least 80% recall divided by focus hours.")),
            LearningMetric(title: tr("Cards due"), value: String(due),
                           detail: tr("Review these to keep the recall curve high.")),
        ]
        if questionCount > 0 {
            metrics.append(LearningMetric(title: tr("Best quiz scores"), value: "\(averageQuiz)/\(questionCount)",
                                          detail: tr("Average of your best results.")))
        }
        for map in workspace.knowledgeMaps {
            let understood = map.stations.filter { $0.mark == .understood || $0.mark == .mastered }.count
            metrics.append(LearningMetric(
                title: map.title, value: "\(understood)/\(map.stations.count)",
                detail: tr("Stations understood or mastered.")
            ))
        }
        return metrics
    }
}

// MARK: - Exam simulator

struct ExamAnswer: Identifiable {
    let id = UUID()
    let question: String
    let expected: String
    var written: String = ""
    var score: Double = 0

    mutating func grade() {
        let typed = Set(LearningWords.normalize(written))
        let wanted = Set(LearningWords.normalize(expected)).filter { $0.count >= 3 }
        guard !wanted.isEmpty else { score = written.isEmpty ? 0 : 1; return }
        let hit = Double(wanted.intersection(typed).count) / Double(wanted.count)
        score = min(1, hit)
    }
}

enum LearningWords {
    static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا").replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}

enum ExamSimulator {
    @MainActor static func build(workspace: WorkspaceStore, store: LibraryStore, limit: Int = 12) -> [ExamAnswer] {
        var questions: [ExamAnswer] = []
        for quiz in workspace.quizzes {
            for question in quiz.questions {
                let choices = question.choices
                let expected = choices.indices.contains(question.answer) ? choices[question.answer] : ""
                let context = store.note(quiz.sourceNoteIDs.first ?? UUID())?.title ?? "Note"
                questions.append(ExamAnswer(question: trMessage("{} — {}", context, question.question), expected: expected))
            }
        }
        for deck in workspace.flashcardDecks {
            for card in deck.cards.prefix(4) {
                questions.append(ExamAnswer(question: card.front, expected: card.back))
            }
        }
        return Array(questions.shuffled().prefix(limit))
    }
}

// MARK: - Arabic semantic matching

/// Arabic word forms differ by prefixes and suffixes; matching canonical
/// forms lets the on-device semantic search find related Arabic passages
/// without sending anything online.
enum ArabicSemantics {
    static func canonical(_ word: String) -> String {
        var value = word
            .replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا").replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
        let prefixes = ["وال", "بال", "كال", "لل", "وان", "ال", "و", "ب", "ك", "ل", "ف"]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes where value.hasPrefix(prefix) && value.count > prefix.count + 2 {
                value.removeFirst(prefix.count)
                changed = true
                break
            }
        }
        let suffixes = ["ون", "ين", "ات", "ها", "ه", "ة", "ي", "و", "ن", "ا"]
        for suffix in suffixes where value.hasSuffix(suffix) && value.count > suffix.count + 2 {
            value.removeLast(suffix.count)
            break
        }
        return value
    }

    static func matchingScore(_ query: Set<String>, _ passage: Set<String>) -> Double {
        let a = Set(query.map { canonical($0) })
        let b = Set(passage.map { canonical($0) })
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.count)
    }
}

// MARK: - Socratic Ghost (optional luxury tier)

/// A quiet, offline margin critic. It spots gaps in study notes with simple
/// language checks and asks one short question. No text leaves the iPad; the
/// owner can promote a question into Ask This Page to use the connected AI.
struct GhostQuestion: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

enum GhostCritic {
    /// Reads a note's own words and returns at most two concise questions.
    static func questions(in text: String) -> [GhostQuestion] {
        let lower = text.lowercased()
        var result: [GhostQuestion] = []
        if lower.contains("because") || lower.contains("therefore") || lower.contains("لذلك") {
            result.append(GhostQuestion(text: tr("What would disprove this?")))
        }
        if lower.contains("increases") || lower.contains("improves") || lower.contains("reduces") || lower.contains("يزيد") {
            result.append(GhostQuestion(text: tr("Compared with what baseline?")))
        }
        if result.isEmpty {
            result.append(GhostQuestion(text: tr("What assumption are you making here?")))
        }
        return Array(result.prefix(2))
    }
}

private func trMessage(_ pattern: String, _ value: String) -> String {
    trMessage(pattern).replacingOccurrences(of: "{}", with: value)
}

private func trMessage(_ pattern: String, _ first: String, _ second: String) -> String {
    var text = trMessage(pattern)
    text = text.replacingOccurrences(of: "{}", with: first)
    text = text.replacingOccurrences(of: "{}", with: second)
    return text
}
