import PDFKit
import SwiftUI

/// The text of a book, page by page, and finding the pages that answer a
/// question, on the iPad. Only those pages are sent to the AI.
struct BookIndex: Sendable {
    /// Text of each PDF page (empty for scans not yet made searchable).
    let pages: [String]
    /// Words of each page and how often they appear.
    private let counts: [[String: Int]]
    /// In how many pages each word appears.
    private let spread: [String: Int]

    init(document: PDFDocument) {
        var pages: [String] = []
        var counts: [[String: Int]] = []
        var spread: [String: Int] = [:]
        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            pages.append(text)
            var words: [String: Int] = [:]
            for word in Self.words(in: text) { words[word, default: 0] += 1 }
            for word in words.keys { spread[word, default: 0] += 1 }
            counts.append(words)
        }
        self.pages = pages
        self.counts = counts
        self.spread = spread
    }

    var hasText: Bool { pages.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 } }

    /// Lowercase, Arabic letters unified, words of three letters or more.
    static func words(in text: String) -> [String] {
        let normalized = CommandParser.normalized(text)
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
            .map { LivingAnalyzer.key(for: $0) }
    }

    /// The pages that best match a question, most useful first, up to about
    /// `limit` characters of text.
    func pages(for question: String, within range: ClosedRange<Int>? = nil, limit: Int = 12_000) -> [Int] {
        let asked = Set(Self.words(in: question))
        guard !asked.isEmpty else { return [] }
        let total = Double(max(pages.count, 1))
        var scores: [(page: Int, score: Double)] = []
        for (index, words) in counts.enumerated() {
            if let range, !range.contains(index) { continue }
            var score: Double = 0
            for word in asked {
                guard let count = words[word] else { continue }
                let rarity: Double = Math.logarithm(total / Double(spread[word] ?? 1)) + 1
                score += Double(count) * rarity
            }
            if score > 0 { scores.append((index, score)) }
        }
        scores.sort { $0.score > $1.score }
        var picked: [Int] = []
        var used = 0
        for item in scores {
            let length = pages[item.page].count
            if used + length > limit, !picked.isEmpty { break }
            picked.append(item.page)
            used += length
            if picked.count >= 8 { break }
        }
        return picked
    }

    /// Pages with their numbers, for the AI to cite: "[p. 12] ...".
    func excerpt(_ pageNumbers: [Int], limit: Int = 14_000) -> String {
        var parts: [String] = []
        var used = 0
        for page in pageNumbers.sorted() where page < pages.count {
            let text = pages[page].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let room = max(limit - used, 0)
            guard room > 200 else { break }
            let piece = String(text.prefix(room))
            parts.append("[p. \(page + 1)]\n\(piece)")
            used += piece.count
        }
        return parts.joined(separator: "\n\n")
    }
}

/// What InkPad asks the AI about a book, and how it reads the answers.
enum BookAI {
    static func askPrompt(question: String, book: String, excerpt: String) -> String {
        [
            "Answer the question from these pages of the book \"\(book)\". Each page starts with its number, like [p. 12].",
            "Cite the pages you used right after each statement, like [p. 12]. If the pages don't answer it, say so and answer from general knowledge, saying that you did.",
            "Explain clearly, like a good tutor. Use Markdown. Reply in the language of the question.",
            "Question: \(question)",
            "Pages:",
            excerpt,
        ].joined(separator: "\n\n")
    }

    static func summaryPrompt(chapter: String, book: String, excerpt: String) -> String {
        [
            "Write study notes of the chapter \"\(chapter)\" from the book \"\(book)\". Each page starts with its number, like [p. 12].",
            "Use Markdown: a \"# \" title, \"## \" sections that follow the chapter, bullet points for key facts, **bold** for key terms, the page numbers in brackets after each section's facts, and a short \"## Summary\" with the 5–8 points to remember. Keep the book's language.",
            "Pages:",
            excerpt,
        ].joined(separator: "\n\n")
    }

    static func glossaryPrompt(chapter: String, excerpt: String) -> String {
        [
            "List the important terms, abbreviations and formulas of the chapter \"\(chapter)\", each with a short clear definition and the page where it is explained. Each page starts with its number, like [p. 12]. Keep the book's language; give the full form of abbreviations.",
            "Reply with JSON only: {\"terms\": [{\"term\": \"...\", \"definition\": \"...\", \"page\": 12}]}",
            "Pages:",
            excerpt,
        ].joined(separator: "\n\n")
    }

    /// Exam-style questions: clinical or practical cases like board exams.
    static func examNotes(_ excerpt: String) -> String {
        "Write the questions in the style of professional board exams (for respiratory care, like NBRC TMC/CSE): short clinical or practical situations, asking what to do, what it means, or what to change, with plausible wrong choices.\n\n" + excerpt
    }

    struct Term: Identifiable {
        let id = UUID()
        let term: String
        let definition: String
        let page: Int?
    }

    static func terms(from reply: String) throws -> [Term] {
        guard let json = AIJSON.object(in: reply), let list = json["terms"] as? [[String: Any]] else { throw AIError.unreadable }
        let terms = list.compactMap { item -> Term? in
            guard let term = item["term"] as? String, let definition = item["definition"] as? String, !term.isEmpty else { return nil }
            let page = (item["page"] as? Int) ?? (item["page"] as? NSNumber)?.intValue ?? Int("\(item["page"] ?? "")")
            return Term(term: term, definition: definition, page: page)
        }
        guard !terms.isEmpty else { throw AIError.empty }
        return terms
    }

    static func glossaryMarkdown(_ terms: [Term], chapter: String, book: String) -> String {
        let lines = terms.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }.map { item -> String in
            let page = item.page.map { " (p. \($0))" } ?? ""
            return "- **\(item.term)**: \(item.definition)\(page)"
        }
        return (["From [[\(book)]], \(chapter). #glossary", ""] + lines).joined(separator: "\n")
    }

    /// Page numbers cited in an answer, like [p. 12] or [pp. 12–14].
    static func citedPages(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"\[pp?\.\s*(\d+)"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var pages: [Int] = []
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text), let page = Int(text[r]), !pages.contains(page) {
                pages.append(page)
            }
        }
        return pages
    }
}

/// One question and its answer in Ask the Book.
struct BookAnswer: Identifiable {
    let id = UUID()
    let question: String
    var answer: String
    var pages: [Int]
}

/// Ask the Book: questions answered from the book's own pages, with the
/// pages cited; tap a page number to go there.
struct AskBookView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var ai = AISettings.shared
    let noteID: UUID
    let bookTitle: String
    let document: PDFDocument?
    /// The chapter being read, to ask about it alone.
    let chapter: BookChapter?
    let goToPage: (Int) -> Void

    @State private var index: BookIndex?
    @State private var question = ""
    @State private var answers: [BookAnswer] = []
    @State private var onlyChapter = false
    @State private var isAsking = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 8) {
            if let problem {
                Text(trMessage(problem)).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            if ai.problem != nil {
                Text("Set up an AI service in AI Settings to ask the book.").font(.callout).foregroundStyle(.secondary).padding()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if answers.isEmpty {
                        Text("Ask anything about the book. The pages that match are found on this iPad; only those are sent to \(ai.provider.title), and the answer cites them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(answers) { item in answerCard(item) }
                }
                .padding(.horizontal)
            }
            if let chapter {
                Toggle("Only “\(chapter.title)”", isOn: $onlyChapter)
                    .font(.caption)
                    .padding(.horizontal)
            }
            HStack {
                TextField("Ask the book…", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .onSubmit(ask)
                Button {
                    ask()
                } label: {
                    if isAsking { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking || ai.problem != nil)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .task {
            guard index == nil, let document else { return }
            index = await Task.detached(priority: .userInitiated) { BookIndex(document: document) }.value
        }
    }

    private func answerCard(_ item: BookAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.question).font(.subheadline.weight(.semibold))
            Text(LocalizedStringKey(item.answer)).font(.callout).textSelection(.enabled)
            if !item.pages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(item.pages, id: \.self) { page in
                            Button("p. \(page)") { goToPage(page - 1) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
            Button {
                let text = "## \(item.question)\n\n\(item.answer)\n\nFrom [[\(bookTitle)]]."
                if store.createTextNote(titled: "Q: \(item.question.prefix(50))", in: store.note(noteID)?.folderID, extraText: text) != nil {
                    CommandCenter.shared.say("Saved as a text note")
                }
            } label: {
                Label("Save as Note", systemImage: "square.and.arrow.down").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .themedCard()
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client = ai.client() else { return }
        guard store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else {
            problem = NoteTexts.firewallMessage(onDevice: client.kind.isOnDevice)
            return
        }
        guard let index, index.hasText else {
            problem = "The book has no text to search yet. If it is scanned, use Make Searchable first."
            return
        }
        let range: ClosedRange<Int>? = onlyChapter ? chapter.map { $0.firstPage...$0.lastPage } : nil
        let pages = index.pages(for: text, within: range)
        var chosen: [Int] = pages
        if chosen.isEmpty {
            // Nothing matched: the start of the chapter (or book) instead.
            let first: Int = range?.lowerBound ?? 0
            let last: Int = min(range?.upperBound ?? 5, index.pages.count - 1)
            chosen = first <= last ? Array(first...last) : []
        }
        let excerpt = index.excerpt(chosen)
        let prompt = BookAI.askPrompt(question: text, book: bookTitle, excerpt: excerpt)
        question = ""
        problem = nil
        isAsking = true
        answers.append(BookAnswer(question: text, answer: "…", pages: []))
        let slot = answers.count - 1
        Task {
            defer { isAsking = false }
            do {
                let reply = try await client.complete(system: "You answer questions about a book from its pages and cite them.", messages: [AIMessage(.user, prompt)])
                answers[slot].answer = reply
                answers[slot].pages = BookAI.citedPages(in: reply)
            } catch {
                answers[slot].answer = "Couldn't answer: \(error.localizedDescription)"
            }
        }
    }
}
