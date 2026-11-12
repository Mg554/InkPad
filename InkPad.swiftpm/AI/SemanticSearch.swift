import Foundation
import NaturalLanguage
import PDFKit

/// A passage that matches a search by meaning.
struct MeaningHit: Identifiable, Equatable {
    let noteID: UUID
    let title: String
    let snippet: String
    /// The PDF page (zero-based), when the passage is from a PDF.
    let pdfPage: Int?
    let score: Double

    var id: String { noteID.uuidString + "-" + String(pdfPage ?? -1) + "-" + String(snippet.prefix(20)) }
}

/// Search by meaning, on the iPad: notes are cut into passages, each turned
/// into a sentence vector (Apple's NaturalLanguage), and the question is
/// compared with them. Languages without a vector model fall back to
/// matching words. When the AI service is ready, the question is also
/// phrased in English and Arabic (only the question is sent), so an Arabic
/// question finds English notes and the other way round.
@MainActor
final class SemanticSearch: ObservableObject {
    static let shared = SemanticSearch()

    private struct Passage: Sendable {
        let noteID: UUID
        let title: String
        let text: String
        let pdfPage: Int?
        let language: String
        let vector: [Double]?
    }

    private var passages: [UUID: [Passage]] = [:]
    /// When each note's passages were made.
    private var builtAt: [UUID: Date] = [:]
    private var expansions: [String: [String]] = [:]
    @Published private(set) var isIndexing = false

    // MARK: Searching

    func search(_ query: String, store: LibraryStore, limit: Int = 8) async -> [MeaningHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        await refresh(store: store)
        let phrasings = [trimmed] + (await expand(trimmed))
        let all: [Passage] = passages.values.flatMap { $0 }
        let scored: [(Passage, Double)] = await Task.detached(priority: .userInitiated) {
            Self.score(all, phrasings: phrasings)
        }.value
        var hits: [MeaningHit] = []
        var perNote: [UUID: Int] = [:]
        for (passage, score) in scored where score > 0.2 {
            let count = perNote[passage.noteID] ?? 0
            guard count < 2 else { continue }
            perNote[passage.noteID] = count + 1
            hits.append(MeaningHit(noteID: passage.noteID, title: passage.title, snippet: Self.snippet(passage.text), pdfPage: passage.pdfPage, score: score))
            if hits.count >= limit { break }
        }
        return hits
    }

    /// The question in English and Arabic, from the AI service (cached).
    private func expand(_ query: String) async -> [String] {
        if let cached = expansions[query] { return cached }
        guard let client = AISettings.shared.client() else { return [] }
        let prompt = [
            "Rewrite this search question for finding notes: give it once in English and once in Arabic, "
                + "each with a few key words. One per line, nothing else.",
            "",
            query,
        ].joined(separator: "\n")
        guard let reply = try? await client.complete(system: "You help search study notes.", messages: [AIMessage(.user, prompt)]) else {
            expansions[query] = []
            return []
        }
        let lines = reply.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let result = Array(lines.prefix(3))
        expansions[query] = result
        return result
    }

    private nonisolated static func score(_ passages: [Passage], phrasings: [String]) -> [(Passage, Double)] {
        // A vector of each phrasing in each language that has a model.
        var queryVectors: [String: [[Double]]] = [:]
        var queryWords: [Set<String>] = []
        for phrase in phrasings {
            queryWords.append(words(phrase))
            let language = detect(phrase)
            if let embedding = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: language)), let vector = embedding.vector(for: phrase) {
                queryVectors[language, default: []].append(vector)
            }
        }
        var results: [(Passage, Double)] = []
        for passage in passages {
            var best: Double = 0
            if let vector = passage.vector, let candidates = queryVectors[passage.language] {
                for query in candidates { best = max(best, cosine(query, vector)) }
            }
            // Words in common still count (names, terms, languages without a model).
            let passageWords = words(passage.text)
            for query in queryWords where !query.isEmpty {
                let shared = Double(query.intersection(passageWords).count) / Double(query.count)
                best = max(best, shared * 0.9)
            }
            if best > 0 { results.append((passage, best)) }
        }
        return results.sorted { $0.1 > $1.1 }
    }

    private nonisolated static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var left: Double = 0
        var right: Double = 0
        for index in a.indices {
            dot += a[index] * b[index]
            left += a[index] * a[index]
            right += b[index] * b[index]
        }
        guard left > 0, right > 0 else { return 0 }
        return dot / (Math.root(left) * Math.root(right))
    }

    /// Lowercased words of 3+ letters, Arabic letters simplified, "ال" dropped.
    nonisolated static func words(_ text: String) -> Set<String> {
        let folded = text.lowercased()
            .replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا").replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
        var result: Set<String> = []
        for raw in folded.components(separatedBy: CharacterSet.alphanumerics.inverted) {
            var word = raw
            if word.hasPrefix("ال"), word.count > 4 { word = String(word.dropFirst(2)) }
            if word.count >= 3, !stopWords.contains(word) { result.insert(word) }
        }
        return result
    }

    private nonisolated static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "are", "was", "what", "how", "why", "which", "from", "into", "about",
        "من", "في", "على", "الى", "عن", "ما", "ماذا", "كيف", "لماذا", "هذا", "هذه", "التي", "الذي",
    ]

    nonisolated static func detect(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    private nonisolated static func snippet(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        return clean.count > 180 ? String(clean.prefix(180)) + "…" : clean
    }

    // MARK: Index

    /// Makes passages for notes that are new or changed since last time.
    func refresh(store: LibraryStore) async {
        var jobs: [(UUID, String, [(String, Int?)])] = []
        let current = Set(store.notes.map(\.id))
        for id in passages.keys where !current.contains(id) {
            passages[id] = nil
            builtAt[id] = nil
        }
        for note in store.notes {
            if let built = builtAt[note.id], built >= note.modifiedAt { continue }
            jobs.append((note.id, note.title, texts(of: note, store: store)))
        }
        guard !jobs.isEmpty else { return }
        isIndexing = true
        defer { isIndexing = false }
        let made: [(UUID, [Passage])] = await Task.detached(priority: .utility) {
            jobs.map { job in (job.0, Self.passages(note: job.0, title: job.1, texts: job.2)) }
        }.value
        let now = Date()
        for (id, list) in made {
            passages[id] = list
            builtAt[id] = now
        }
    }

    /// The note's words: Markdown, PDF text page by page, or recognized handwriting.
    private func texts(of note: NoteSummary, store: LibraryStore) -> [(String, Int?)] {
        if note.isText {
            return [(store.textIndex[note.id]?.text ?? "", nil)]
        }
        var result: [(String, Int?)] = []
        if note.hasPDF == true, let content = try? store.loadContent(for: note.id), let document = content.pdf?.pdfDocument {
            let count = min(document.pageCount, 400)
            for index in 0..<count {
                if let text = document.page(at: index)?.string, !text.isEmpty { result.append((text, index)) }
            }
        }
        if let ink = store.recognizedText[note.id], !ink.isEmpty, result.isEmpty {
            result.append((ink, nil))
        }
        result.append((note.title, nil))
        return result
    }

    private nonisolated static func passages(note: UUID, title: String, texts: [(String, Int?)]) -> [Passage] {
        var result: [Passage] = []
        var models: [String: NLEmbedding] = [:]
        for (text, page) in texts {
            for chunk in chunks(text) {
                let language = detect(chunk)
                if models[language] == nil, let model = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: language)) {
                    models[language] = model
                }
                let vector = models[language]?.vector(for: chunk)
                result.append(Passage(noteID: note, title: title, text: chunk, pdfPage: page, language: language, vector: vector))
            }
        }
        return result
    }

    /// Pieces of about 400 characters, cut between sentences.
    private nonisolated static func chunks(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        var result: [String] = []
        var current = ""
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if current.count + sentence.count > 400, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + sentence
            return true
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

import SwiftUI

/// "By Meaning" results under the library's search.
struct MeaningResults: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var search = SemanticSearch.shared
    let query: String
    let open: (MeaningHit) -> Void
    @State private var hits: [MeaningHit] = []
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("By Meaning", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if isSearching || search.isIndexing { ProgressView().controlSize(.small) }
            }
            if hits.isEmpty, !isSearching {
                Text("No passages found by meaning.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(hits) { hit in
                Button {
                    open(hit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: hit.title).font(.subheadline.weight(.semibold))
                            if let page = hit.pdfPage {
                                Text("p. \(page + 1)").font(.caption.weight(.semibold)).foregroundStyle(Color.inkAccent)
                            }
                            Spacer()
                            Text("\(Int(hit.score * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        Text(verbatim: hit.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .task(id: query) {
            // Wait for typing to pause.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            isSearching = true
            hits = await search.search(query, store: store)
            isSearching = false
        }
    }
}
