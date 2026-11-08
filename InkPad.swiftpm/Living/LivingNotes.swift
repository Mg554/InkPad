import NaturalLanguage
import SwiftUI

/// Living Notes settings (the bubble's menu).
struct LivingSettings: StoredLook {
    static let storageKey = "livingSettings"

    var isOn = true
    /// Concepts underlined in text notes, tappable in the preview.
    var highlightsConcepts = true
    /// Small bubbles next to handwriting that matches other notes.
    var inkBubbles = true
    /// Notes where Living Notes is turned off.
    var offNotes: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = container.value(.isOn, or: isOn)
        highlightsConcepts = container.value(.highlightsConcepts, or: highlightsConcepts)
        inkBubbles = container.value(.inkBubbles, or: inkBubbles)
        offNotes = container.value(.offNotes, or: offNotes)
    }

    func isOn(for id: UUID) -> Bool { isOn && !offNotes.contains(id.uuidString) }
}

/// Connects what you write to what you wrote before, on the iPad: the
/// concepts in each note, notes that talk about the same things, links to
/// suggest, and what's new since a note was last opened. Nothing is sent
/// anywhere; "Explain the Connection" uses AI only when asked, through the
/// AI Firewall.
@MainActor
final class LivingNotes: ObservableObject {
    static let shared = LivingNotes()

    struct Related: Identifiable {
        let id: UUID
        let score: Double
        /// Concepts both notes talk about, most telling first.
        let shared: [String]
        let snippet: String
        let isLinked: Bool
    }

    struct Concept: Identifiable, Hashable {
        var id: String { key }
        let key: String
        let display: String
        /// How many other notes mention it.
        let otherNotes: Int
    }

    struct Mention: Identifiable {
        var id: UUID { noteID }
        let noteID: UUID
        let title: String
        let date: Date
        let snippet: String
    }

    @Published var settings = LivingSettings.load() {
        didSet { settings.save() }
    }
    /// Changes when the index is rebuilt, so views refresh.
    @Published private(set) var revision = 0

    /// Per note: concept key → weight.
    private var vectors: [UUID: [String: Double]] = [:]
    private var displays: [String: String] = [:]
    /// How many notes mention each concept.
    private var documentCount: [String: Int] = [:]
    private var embeddings: [UUID: [Double]] = [:]
    private var texts: [UUID: String] = [:]
    private var builtFor: [UUID: Date] = [:]
    private var rebuildTask: Task<Void, Never>?

    // MARK: Links and visits

    private static let linksKey = "livingLinks"
    private static let dismissedKey = "livingDismissed"
    private static let seenKey = "livingLastSeen"
    @Published private(set) var acceptedLinks: Set<String> = Set(UserDefaults.standard.stringArray(forKey: linksKey) ?? [])
    private var dismissedLinks: Set<String> = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])

    static func pair(_ a: UUID, _ b: UUID) -> String {
        [a.uuidString, b.uuidString].sorted().joined(separator: "|")
    }

    func accept(_ a: UUID, _ b: UUID) {
        acceptedLinks.insert(Self.pair(a, b))
        UserDefaults.standard.set(Array(acceptedLinks), forKey: Self.linksKey)
        revision += 1
    }

    func dismiss(_ a: UUID, _ b: UUID) {
        dismissedLinks.insert(Self.pair(a, b))
        UserDefaults.standard.set(Array(dismissedLinks), forKey: Self.dismissedKey)
        revision += 1
    }

    func unlink(_ a: UUID, _ b: UUID) {
        acceptedLinks.remove(Self.pair(a, b))
        UserDefaults.standard.set(Array(acceptedLinks), forKey: Self.linksKey)
        revision += 1
    }

    /// Accepted links as pairs of note ids (for the Graph).
    var linkPairs: [(UUID, UUID)] {
        acceptedLinks.compactMap { pair in
            let parts = pair.split(separator: "|").compactMap { UUID(uuidString: String($0)) }
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }

    func lastSeen(_ id: UUID) -> Date? {
        let seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Double] ?? [:]
        return seen[id.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    func markSeen(_ id: UUID) {
        var seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Double] ?? [:]
        seen[id.uuidString] = Date().timeIntervalSince1970
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
    }

    // MARK: Index

    /// Re-reads notes that changed, in the background.
    func refresh(store: LibraryStore) {
        let notes = store.notes
        var inputs: [UUID: String] = [:]
        var stamps: [UUID: Date] = [:]
        for note in notes {
            let text = [note.title, store.textIndex[note.id]?.text ?? "", store.recognizedText[note.id] ?? ""].joined(separator: "\n")
            inputs[note.id] = text
            stamps[note.id] = note.modifiedAt
        }
        let changed: [UUID: String] = inputs.filter { (item: (key: UUID, value: String)) -> Bool in
            let stampChanged: Bool = builtFor[item.key] != stamps[item.key]
            let textChanged: Bool = texts[item.key] != item.value
            return stampChanged || textChanged
        }
        let removed = Set(texts.keys).subtracting(inputs.keys)
        guard !changed.isEmpty || !removed.isEmpty else { return }
        rebuildTask?.cancel()
        rebuildTask = Task {
            let analyzed = await Task.detached(priority: .utility) {
                changed.mapValues { LivingAnalyzer.analyze($0) }
            }.value
            guard !Task.isCancelled else { return }
            for id in removed {
                vectors[id] = nil
                embeddings[id] = nil
                texts[id] = nil
                builtFor[id] = nil
            }
            for (id, result) in analyzed {
                vectors[id] = result.terms
                embeddings[id] = result.embedding
                texts[id] = changed[id]
                builtFor[id] = stamps[id]
                for (key, display) in result.displays where displays[key] == nil { displays[key] = display }
            }
            documentCount = [:]
            for vector in vectors.values {
                for key in vector.keys { documentCount[key, default: 0] += 1 }
            }
            revision += 1
        }
    }

    private func idf(_ key: String) -> Double {
        let total = Double(max(vectors.count, 1))
        let count: Int = documentCount[key] ?? 0
        let ratio: Double = (total + 1) / Double(count + 1)
        return Math.logarithm(ratio) + 1
    }

    private func weighted(_ vector: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (key, value) in vector {
            result[key] = value * idf(key)
        }
        return result
    }

    // MARK: Questions

    /// Notes that talk about the same things as `id` (or as `liveText`
    /// while it is being written).
    func related(to id: UUID, liveText: String? = nil, store: LibraryStore, limit: Int = 12) -> [Related] {
        let mine: [String: Double]
        var myEmbedding = embeddings[id]
        if let liveText {
            let analyzed = LivingAnalyzer.analyze(liveText)
            mine = analyzed.terms
            myEmbedding = analyzed.embedding ?? myEmbedding
        } else {
            mine = vectors[id] ?? [:]
        }
        guard !mine.isEmpty else { return [] }
        let a = weighted(mine)
        var results: [Related] = []
        for (other, vector) in vectors where other != id && store.note(other) != nil {
            let b = weighted(vector)
            var score = Self.cosine(a, b)
            if let e1 = myEmbedding, let e2 = embeddings[other] {
                let meaning: Double = max(Self.cosine(e1, e2), 0)
                score = score * 0.65 + meaning * 0.35
            }
            // Only concepts in more than one note count as shared.
            let common: [String] = a.keys.filter { (key: String) -> Bool in
                let inMore: Bool = (documentCount[key] ?? 0) >= 2
                return b[key] != nil && inMore
            }
            func strength(_ key: String) -> Double {
                let mineWeight: Double = a[key] ?? 0
                let otherWeight: Double = b[key] ?? 0
                return mineWeight * otherWeight
            }
            let shared: [String] = common.sorted { strength($0) > strength($1) }
            guard score > 0.08, !shared.isEmpty else { continue }
            let names = shared.prefix(5).map { displays[$0] ?? $0 }
            results.append(Related(
                id: other, score: score, shared: names,
                snippet: snippet(in: other, around: names.first ?? ""),
                isLinked: acceptedLinks.contains(Self.pair(id, other)) || isTextLinked(id, other, store: store)
            ))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Strong matches not yet linked, to suggest.
    func suggestedLinks(for id: UUID, store: LibraryStore) -> [Related] {
        related(to: id, store: store).filter { (item: Related) -> Bool in
            let dismissed: Bool = dismissedLinks.contains(Self.pair(id, item.id))
            return !item.isLinked && item.score >= 0.14 && !dismissed
        }
    }

    /// Related notes changed since this note was last opened.
    func newSinceLastVisit(_ id: UUID, store: LibraryStore) -> [Related] {
        guard let seen = lastSeen(id) else { return [] }
        return related(to: id, store: store).filter { (item: Related) -> Bool in
            let modified: Date = store.note(item.id)?.modifiedAt ?? .distantPast
            return modified > seen
        }
    }

    /// Concepts in this note that other notes also mention.
    func concepts(in id: UUID, liveText: String? = nil) -> [Concept] {
        let mine = liveText.map { LivingAnalyzer.analyze($0).terms } ?? vectors[id] ?? [:]
        return mine.keys
            .compactMap { key -> Concept? in
                let total: Int = documentCount[key] ?? 0
                let inThisNote: Bool = vectors[id]?[key] != nil
                let others: Int = inThisNote ? total - 1 : total
                guard others >= 1 else { return nil }
                return Concept(key: key, display: displays[key] ?? key, otherNotes: others)
            }
            .sorted { (a: Concept, b: Concept) -> Bool in
                if a.otherNotes != b.otherNotes { return a.otherNotes > b.otherNotes }
                let weightA: Double = mine[a.key] ?? 0
                let weightB: Double = mine[b.key] ?? 0
                return weightA > weightB
            }
    }

    /// Concepts from `text` (for example handwriting just written) that other notes mention.
    func knownConcepts(in text: String, excluding id: UUID) -> [Concept] {
        concepts(in: id, liveText: text)
    }

    /// Everything written about a concept, oldest first.
    func mentions(of conceptKey: String, store: LibraryStore) -> [Mention] {
        let display = displays[conceptKey] ?? conceptKey
        return vectors.compactMap { id, vector -> Mention? in
            guard vector[conceptKey] != nil, let note = store.note(id) else { return nil }
            return Mention(noteID: id, title: note.title, date: note.createdAt, snippet: snippet(in: id, around: display, length: 220))
        }
        .sorted { $0.date < $1.date }
    }

    func conceptKey(for text: String) -> String {
        let key = LivingAnalyzer.key(for: text)
        if displays[key] != nil { return key }
        return displays.first { $0.value.caseInsensitiveCompare(text) == .orderedSame }?.key ?? key
    }

    func display(of key: String) -> String { displays[key] ?? key }

    /// Flashcard decks made from this note, or with cards about its concepts.
    func decks(for id: UUID, workspace: WorkspaceStore) -> [FlashcardDeck] {
        let names = concepts(in: id).prefix(15).map(\.display)
        return workspace.flashcardDecks.filter { deck in
            deck.sourceNoteIDs.contains(id) || deck.cards.contains { card in
                names.contains { card.front.localizedCaseInsensitiveContains($0) || card.back.localizedCaseInsensitiveContains($0) }
            }
        }
    }

    private func isTextLinked(_ a: UUID, _ b: UUID, store: LibraryStore) -> Bool {
        func links(_ from: UUID, _ to: UUID) -> Bool {
            guard let target = store.note(to) else { return false }
            return store.textIndex[from]?.links.contains { NoteLinks.key($0.title) == NoteLinks.key(target.title) } ?? false
        }
        return links(a, b) || links(b, a)
    }

    func snippet(in id: UUID, around word: String, length: Int = 120) -> String {
        guard let text = texts[id] else { return "" }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard !word.isEmpty, let range = flat.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flat.prefix(length))
        }
        let start = flat.index(range.lowerBound, offsetBy: -length / 3, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: length * 2 / 3, limitedBy: flat.endIndex) ?? flat.endIndex
        let before: String = start > flat.startIndex ? "…" : ""
        let after: String = end < flat.endIndex ? "…" : ""
        return before + String(flat[start..<end]) + after
    }

    static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        var dot: Double = 0
        var sumA: Double = 0
        var sumB: Double = 0
        for (key, value) in a {
            dot += value * (b[key] ?? 0)
            sumA += value * value
        }
        for value in b.values {
            sumB += value * value
        }
        let na: Double = Math.root(sumA)
        let nb: Double = Math.root(sumB)
        return na > 0 && nb > 0 ? dot / (na * nb) : 0
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (Math.root(na) * Math.root(nb))
    }
}

/// Reads the concepts in a text with Apple's NaturalLanguage, on the iPad.
enum LivingAnalyzer {
    struct Result: Sendable {
        var terms: [String: Double]
        var displays: [String: String]
        var embedding: [Double]?
    }

    private static let stopwords: Set<String> = [
        "this", "that", "with", "from", "have", "were", "will", "your", "what", "when", "which", "there", "their", "about",
        "would", "could", "should", "these", "those", "into", "than", "then", "them", "they", "been", "also", "some", "more",
        "most", "very", "just", "like", "only", "over", "such", "each", "other", "after", "before", "because", "while", "where",
        "note", "notes", "untitled", "page", "thing", "things", "today", "time", "inside", "app", "backup",
        "هذا", "هذه", "ذلك", "التي", "الذي", "الذين", "على", "الى", "إلى", "عن", "من", "في", "مع", "كان", "كانت", "يكون",
        "لكن", "بعد", "قبل", "عند", "كل", "بين", "حتى", "اذا", "إذا", "ايضا", "أيضا", "هناك", "هنا", "لان", "لأن", "ملاحظه",
        "minus", "plus", "increase", "increases", "decrease", "decreases", "reduce", "reduces", "include", "includes",
        "equal", "equals", "lead", "leads", "guide", "guides", "help", "helps", "keep", "keeps", "make", "makes",
        "show", "shows", "use", "uses", "set", "sets", "reach", "appear", "appears", "rise", "rises", "deliver", "delivers",
    ]

    /// Words that make a two-word phrase a fragment of a sentence, not a concept.
    private static let phraseBreakers: Set<String> = [
        "minus", "plus", "increase", "increases", "decrease", "decreases", "reduce", "reduces", "include", "includes",
        "equal", "equals", "lead", "leads", "guide", "guides", "help", "helps", "keep", "keeps", "make", "makes",
        "show", "shows", "use", "uses", "set", "sets", "reach", "appear", "appears", "rise", "rises", "deliver", "delivers",
        "may", "can", "will", "is", "are", "was", "were", "be", "been", "the", "and", "or", "of", "to", "in", "with",
    ]

    /// The matching key of a word or phrase.
    static func key(for text: String) -> String {
        var key = CommandParser.normalized(text).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        // Arabic: drop the article so الضغط and ضغط match.
        if key.hasPrefix("ال"), key.count > 4 { key.removeFirst(2) }
        if key.hasSuffix("s"), key.count > 4, !key.hasSuffix("ss"), key.allSatisfy({ $0.isASCII }) { key.removeLast() }
        return key
    }

    static func analyze(_ text: String) -> Result {
        var terms: [String: Double] = [:]
        var displays: [String: String] = [:]
        func add(_ display: String, weight: Double) {
            let cleaned = display.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            let k = key(for: cleaned)
            if cleaned.contains(" ") {
                let words = cleaned.lowercased().split(separator: " ").map(String.init)
                if words.contains(where: { phraseBreakers.contains($0) }) { return }
            }
            guard k.count >= 3, !stopwords.contains(k), !stopwords.contains(cleaned.lowercased()), !k.allSatisfy(\.isNumber) else { return }
            terms[k, default: 0] += weight
            if displays[k] == nil { displays[k] = cleaned }
        }

        // Acronyms and terms like PEEP, FiO2, SBT count a lot.
        if let acronyms = try? NSRegularExpression(pattern: #"\b[A-Z][A-Za-z]*[A-Z0-9][A-Za-z0-9]*\b"#) {
            let range = NSRange(text.startIndex..., in: text)
            for match in acronyms.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { add(String(text[r]), weight: 2) }
            }
        }
        for tag in NoteLinks.tags(in: text) { add(tag, weight: 2) }
        for link in NoteLinks.links(in: text) { add(link.title, weight: 2) }

        // Nouns, names, and two-word noun phrases.
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = text
        var previous: (word: String, isModifier: Bool)?
        var previousEnd = text.startIndex
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = String(text[range])
            // Phrases don't run across lines or punctuation.
            let gap = text[previousEnd..<range.lowerBound]
            if gap.contains(where: { $0.isNewline || ($0.isPunctuation && $0 != "-") }) { previous = nil }
            previousEnd = range.upperBound
            let isNoun = tag == .noun || tag == .otherWord
            let isAdjective = tag == .adjective
            let isArabic: Bool = word.unicodeScalars.contains { (scalar: Unicode.Scalar) -> Bool in
                scalar.value >= 0x0600 && scalar.value <= 0x06FF
            }
            if isArabic {
                // Arabic tagging is limited: longer words carry the meaning.
                if word.count >= 4 { add(word, weight: 1) }
                if let previous, previous.isModifier, word.count >= 3 { add(previous.word + " " + word, weight: 1.5) }
                previous = (word, word.count >= 3)
                return true
            }
            if isNoun, word.count >= 4 {
                let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? word
                add(lemma.count >= 3 ? lemma : word, weight: 1)
                if let previous, previous.isModifier { add(previous.word + " " + word, weight: 1.5) }
            }
            previous = (word, isNoun || isAdjective)
            return true
        }
        // Words seen once in a long text say little.
        let wordCount = Double(max(text.split(whereSeparator: \.isWhitespace).count, 1))
        if wordCount > 120 {
            terms = terms.filter { (item: (key: String, value: Double)) -> Bool in
                item.value >= 2 || item.key.contains(" ")
            }
        }
        return Result(terms: terms, displays: displays, embedding: embedding(of: text))
    }

    /// A meaning vector for English text (Apple's sentence embedding).
    private static func embedding(of text: String) -> [Double]? {
        guard NLLanguageRecognizer.dominantLanguage(for: text) == .english,
              let model = NLEmbedding.sentenceEmbedding(for: .english)
        else { return nil }
        return model.vector(for: String(text.prefix(1500)))
    }
}
