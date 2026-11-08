import PDFKit
import SwiftUI

/// How a chapter changed between two editions of a book.
enum ChapterChangeKind: String, CaseIterable, Identifiable {
    case changed, added, removed, same

    var id: Self { self }

    var title: String {
        switch self {
        case .changed: "Changed"
        case .added: "New"
        case .removed: "Removed"
        case .same: "Same"
        }
    }

    var systemImage: String {
        switch self {
        case .changed: "pencil.circle.fill"
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .same: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .changed: Color.orange
        case .added: Color.green
        case .removed: Color.red
        case .same: Color.gray
        }
    }
}

/// One chapter of the new edition and the chapter it came from.
struct ChapterChange: Identifiable {
    let id = UUID()
    let kind: ChapterChangeKind
    let old: BookChapter?
    let new: BookChapter?
    /// How much of the text is the same, 0...1.
    let similarity: Double

    var title: String { new?.title ?? old?.title ?? "" }

    var percentChanged: Int {
        let changed: Double = (1 - similarity) * 100
        return Int(changed.rounded())
    }

    var pagesLabel: String {
        let oldLabel: String = old.map { $0.pageLabel } ?? "—"
        let newLabel: String = new.map { $0.pageLabel } ?? "—"
        return "\(oldLabel) → \(newLabel)"
    }
}

/// Two editions read and matched chapter by chapter.
struct EditionComparison {
    let oldTitle: String
    let newTitle: String
    /// Text of every page.
    let oldPages: [String]
    let newPages: [String]
    /// Overlapping three-word pieces of every page, to match pages.
    let oldShingles: [Set<Int>]
    let newShingles: [Set<Int>]
    let changes: [ChapterChange]
    /// False when a book had no chapters (outline): parts of 10 pages were compared.
    let usedOutline: Bool
    /// Pages without text (scans that need Make Searchable first).
    let scannedPages: Int

    func count(_ kind: ChapterChangeKind) -> Int {
        changes.filter { $0.kind == kind }.count
    }

    /// The old page most like a new page, looking in `range` first.
    func oldPage(matching newPage: Int, in range: ClosedRange<Int>? = nil) -> Int? {
        guard newPage >= 0, newPage < newShingles.count else { return nil }
        return EditionCompare.bestMatch(for: newShingles[newPage], among: oldShingles, in: range, near: proportional(newPage, from: newPages.count, to: oldPages.count))
    }

    /// The new page most like an old page, looking in `range` first.
    func newPage(matching oldPage: Int, in range: ClosedRange<Int>? = nil) -> Int? {
        guard oldPage >= 0, oldPage < oldShingles.count else { return nil }
        return EditionCompare.bestMatch(for: oldShingles[oldPage], among: newShingles, in: range, near: proportional(oldPage, from: oldPages.count, to: newPages.count))
    }

    private func proportional(_ page: Int, from count: Int, to other: Int) -> Int {
        guard count > 0 else { return 0 }
        let ratio: Double = Double(page) / Double(count)
        return Int(ratio * Double(other))
    }

    /// Sentences only in the new chapter and only in the old one.
    func sentenceChanges(of change: ChapterChange, limit: Int = 40) -> (added: [String], removed: [String]) {
        let oldText: String = change.old.map { text(of: $0, in: oldPages) } ?? ""
        let newText: String = change.new.map { text(of: $0, in: newPages) } ?? ""
        let oldSentences = EditionCompare.sentences(in: oldText)
        let newSentences = EditionCompare.sentences(in: newText)
        let oldKeys = Set(oldSentences.map(EditionCompare.sentenceKey))
        let newKeys = Set(newSentences.map(EditionCompare.sentenceKey))
        let added = EditionCompare.unique(newSentences.filter { !oldKeys.contains(EditionCompare.sentenceKey($0)) })
        let removed = EditionCompare.unique(oldSentences.filter { !newKeys.contains(EditionCompare.sentenceKey($0)) })
        return (Array(added.prefix(limit)), Array(removed.prefix(limit)))
    }

    private func text(of chapter: BookChapter, in pages: [String]) -> String {
        let first = max(chapter.firstPage, 0)
        let last = min(chapter.lastPage, pages.count - 1)
        guard first <= last else { return "" }
        return pages[first...last].joined(separator: "\n")
    }
}

/// A piece of a word-by-word comparison of two pages.
struct WordRun {
    /// Where it is in the page's text.
    let range: NSRange
}

/// Compares two editions of a book on the iPad: chapters matched by title
/// and text, pages matched by their words, words compared one by one.
enum EditionCompare {
    // MARK: Whole books

    static func compare(old: PDFDocument, new: PDFDocument, oldTitle: String, newTitle: String, progress: @escaping @Sendable (Double) -> Void) -> EditionComparison {
        let oldPages = pageTexts(old, progress: { progress($0 * 0.45) })
        let newPages = pageTexts(new, progress: { progress(0.45 + $0 * 0.45) })
        let oldShingles = oldPages.map { shingles(words(in: $0)) }
        let newShingles = newPages.map { shingles(words(in: $0)) }
        var oldChapters = PDFToolKit.chapters(of: old, maxDepth: 0)
        var newChapters = PDFToolKit.chapters(of: new, maxDepth: 0)
        let usedOutline = !oldChapters.isEmpty && !newChapters.isEmpty
        if !usedOutline {
            oldChapters = parts(count: oldPages.count)
            newChapters = parts(count: newPages.count)
        }
        let oldSets = oldChapters.map { union(of: $0, in: oldShingles) }
        let newSets = newChapters.map { union(of: $0, in: newShingles) }
        let changes = match(oldChapters: oldChapters, newChapters: newChapters, oldSets: oldSets, newSets: newSets, byTitle: usedOutline)
        progress(1)
        let empty = oldPages.filter { $0.count < 20 }.count + newPages.filter { $0.count < 20 }.count
        return EditionComparison(
            oldTitle: oldTitle, newTitle: newTitle,
            oldPages: oldPages, newPages: newPages,
            oldShingles: oldShingles, newShingles: newShingles,
            changes: changes, usedOutline: usedOutline, scannedPages: empty
        )
    }

    private static func pageTexts(_ document: PDFDocument, progress: (Double) -> Void) -> [String] {
        var texts: [String] = []
        let total = max(document.pageCount, 1)
        for index in 0..<document.pageCount {
            autoreleasepool {
                let text = document.page(at: index)?.string ?? ""
                texts.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if index % 20 == 0 { progress(Double(index) / Double(total)) }
        }
        return texts
    }

    /// Parts of 10 pages, for books without chapters.
    private static func parts(count: Int) -> [BookChapter] {
        var parts: [BookChapter] = []
        var first = 0
        while first < count {
            let last = min(first + 9, count - 1)
            parts.append(BookChapter(id: "part-\(first)", title: "Pages \(first + 1)–\(last + 1)", firstPage: first, lastPage: last, depth: 0))
            first = last + 1
        }
        return parts
    }

    private static func union(of chapter: BookChapter, in pages: [Set<Int>]) -> Set<Int> {
        var result: Set<Int> = []
        let first = max(chapter.firstPage, 0)
        let last = min(chapter.lastPage, pages.count - 1)
        guard first <= last else { return result }
        for index in first...last { result.formUnion(pages[index]) }
        return result
    }

    /// Pairs chapters: the same title first, then the most similar text.
    private static func match(oldChapters: [BookChapter], newChapters: [BookChapter], oldSets: [Set<Int>], newSets: [Set<Int>], byTitle: Bool) -> [ChapterChange] {
        var usedOld: Set<Int> = []
        var pairs: [Int: (old: Int, score: Double)] = [:]
        if byTitle {
            let oldKeys = oldChapters.map { titleKey($0.title) }
            for (newIndex, chapter) in newChapters.enumerated() {
                let key = titleKey(chapter.title)
                guard !key.isEmpty else { continue }
                if let oldIndex = oldKeys.indices.first(where: { !usedOld.contains($0) && oldKeys[$0] == key }) {
                    usedOld.insert(oldIndex)
                    pairs[newIndex] = (oldIndex, similarity(oldSets[oldIndex], newSets[newIndex]))
                }
            }
        }
        for newIndex in newChapters.indices where pairs[newIndex] == nil {
            var best: (index: Int, score: Double)?
            for oldIndex in oldChapters.indices where !usedOld.contains(oldIndex) {
                let score = similarity(oldSets[oldIndex], newSets[newIndex])
                if score > (best?.score ?? 0.25) { best = (oldIndex, score) }
            }
            if let best {
                usedOld.insert(best.index)
                pairs[newIndex] = (best.index, best.score)
            }
        }
        var changes: [ChapterChange] = []
        for (newIndex, chapter) in newChapters.enumerated() {
            if let pair = pairs[newIndex] {
                let kind: ChapterChangeKind = pair.score >= 0.95 ? .same : .changed
                changes.append(ChapterChange(kind: kind, old: oldChapters[pair.old], new: chapter, similarity: pair.score))
            } else {
                changes.append(ChapterChange(kind: .added, old: nil, new: chapter, similarity: 0))
            }
        }
        // Removed chapters go where they were in the old book.
        for oldIndex in oldChapters.indices where !usedOld.contains(oldIndex) {
            let removed = ChapterChange(kind: .removed, old: oldChapters[oldIndex], new: nil, similarity: 0)
            let next = changes.firstIndex { ($0.old?.firstPage ?? -1) > oldChapters[oldIndex].firstPage }
            changes.insert(removed, at: next ?? changes.count)
        }
        return changes
    }

    // MARK: Text pieces

    /// Lowercase words, Arabic letters unified.
    static func words(in text: String) -> [String] {
        CommandParser.normalized(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Overlapping three-word pieces, hashed.
    static func shingles(_ words: [String]) -> Set<Int> {
        guard words.count >= 3 else { return Set(words.map { $0.hashValue }) }
        var result: Set<Int> = []
        for index in 0..<(words.count - 2) {
            var hasher = Hasher()
            hasher.combine(words[index])
            hasher.combine(words[index + 1])
            hasher.combine(words[index + 2])
            result.insert(hasher.finalize())
        }
        return result
    }

    static func similarity(_ a: Set<Int>, _ b: Set<Int>) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let shared: Int = a.intersection(b).count
        let all: Int = a.count + b.count - shared
        return all == 0 ? 0 : Double(shared) / Double(all)
    }

    static func bestMatch(for page: Set<Int>, among pages: [Set<Int>], in range: ClosedRange<Int>?, near guess: Int) -> Int? {
        guard !pages.isEmpty else { return nil }
        let window: ClosedRange<Int>
        if let range {
            window = max(range.lowerBound, 0)...min(range.upperBound, pages.count - 1)
        } else {
            window = max(guess - 60, 0)...min(guess + 60, pages.count - 1)
        }
        var best: (index: Int, score: Double)?
        for index in window {
            let score = similarity(page, pages[index])
            if score > (best?.score ?? 0.15) { best = (index, score) }
        }
        if best == nil, range == nil {
            for index in pages.indices where !window.contains(index) {
                let score = similarity(page, pages[index])
                if score > (best?.score ?? 0.15) { best = (index, score) }
            }
        }
        return best?.index
    }

    /// A chapter title without numbers and words like "Chapter".
    static func titleKey(_ title: String) -> String {
        let skip: Set<String> = ["chapter", "part", "section", "unit", "الفصل", "الباب", "فصل"]
        return words(in: title)
            .filter { !skip.contains($0) && Int($0) == nil }
            .joined(separator: " ")
    }

    static func sentences(in text: String) -> [String] {
        let flat = text.replacingOccurrences(of: "-\n", with: "").replacingOccurrences(of: "\n", with: " ")
        var result: [String] = []
        flat.enumerateSubstrings(in: flat.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.count >= 25 { result.append(clean) }
        }
        return result
    }

    /// Each sentence once, in order.
    static func unique(_ sentences: [String]) -> [String] {
        var seen: Set<String> = []
        return sentences.filter { seen.insert(sentenceKey($0)).inserted }
    }

    static func sentenceKey(_ sentence: String) -> String {
        words(in: sentence).joined(separator: " ")
    }

    // MARK: Word by word

    /// Words of a page's text with where each one is.
    private static func tokens(of text: String) -> [(word: String, range: NSRange)] {
        let string = text as NSString
        var result: [(String, NSRange)] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { word, range, _, _ in
            guard let word else { return }
            result.append((CommandParser.normalized(word), range))
        }
        return result
    }

    /// The words only in `old` and the words only in `new`, as runs of text.
    static func wordChanges(old: String, new: String) -> (removed: [WordRun], added: [WordRun]) {
        let a = tokens(of: old)
        let b = tokens(of: new)
        let n = a.count
        let m = b.count
        guard n > 0 || m > 0 else { return ([], []) }
        // Long pages: compare as sets of words instead of in order.
        if n * m > 4_000_000 || n == 0 || m == 0 {
            let aWords = Set(a.map { $0.word })
            let bWords = Set(b.map { $0.word })
            let removed = a.filter { !bWords.contains($0.word) }.map { WordRun(range: $0.range) }
            let added = b.filter { !aWords.contains($0.word) }.map { WordRun(range: $0.range) }
            return (merged(removed, in: old), merged(added, in: new))
        }
        // Longest common subsequence, from the end.
        let width = m + 1
        var table = [Int32](repeating: 0, count: (n + 1) * width)
        var i = n - 1
        while i >= 0 {
            var j = m - 1
            while j >= 0 {
                let here = i * width + j
                if a[i].word == b[j].word {
                    table[here] = table[(i + 1) * width + j + 1] + 1
                } else {
                    let down: Int32 = table[(i + 1) * width + j]
                    let right: Int32 = table[here + 1]
                    table[here] = max(down, right)
                }
                j -= 1
            }
            i -= 1
        }
        var removed: [WordRun] = []
        var added: [WordRun] = []
        i = 0
        var j = 0
        while i < n && j < m {
            if a[i].word == b[j].word {
                i += 1
                j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                removed.append(WordRun(range: a[i].range))
                i += 1
            } else {
                added.append(WordRun(range: b[j].range))
                j += 1
            }
        }
        while i < n {
            removed.append(WordRun(range: a[i].range))
            i += 1
        }
        while j < m {
            added.append(WordRun(range: b[j].range))
            j += 1
        }
        return (merged(removed, in: old), merged(added, in: new))
    }

    /// Joins runs that only have spaces between them.
    private static func merged(_ runs: [WordRun], in text: String) -> [WordRun] {
        let string = text as NSString
        var result: [NSRange] = []
        for run in runs {
            if let last = result.last {
                let gapStart = last.location + last.length
                let gapLength = run.range.location - gapStart
                if gapLength >= 0, gapLength <= 3 {
                    let gap = string.substring(with: NSRange(location: gapStart, length: gapLength))
                    if gap.trimmingCharacters(in: .whitespaces).isEmpty {
                        result[result.count - 1] = NSRange(location: last.location, length: run.range.location + run.range.length - last.location)
                        continue
                    }
                }
            }
            result.append(run.range)
        }
        return result.map { WordRun(range: $0) }
    }

    // MARK: Pictures

    /// The page with runs of its text marked in a color.
    static func image(of page: PDFPage, marking runs: [WordRun], color: UIColor, width: CGFloat = 700) -> UIImage {
        let box = page.bounds(for: .cropBox)
        let factor: CGFloat = width / max(box.width, 1)
        let size = CGSize(width: width, height: box.height * factor)
        let base = page.thumbnail(of: size, for: .cropBox)
        guard page.rotation == 0, !runs.isEmpty else { return base }
        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { context in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            let scaleX: CGFloat = base.size.width / max(box.width, 1)
            let scaleY: CGFloat = base.size.height / max(box.height, 1)
            context.cgContext.setFillColor(color.withAlphaComponent(0.35).cgColor)
            for run in runs.prefix(600) {
                guard let selection = page.selection(for: run.range) else { continue }
                for line in selection.selectionsByLine() {
                    let rect = line.bounds(for: page)
                    let x: CGFloat = (rect.minX - box.minX) * scaleX
                    let y: CGFloat = (box.maxY - rect.maxY) * scaleY
                    let marked = CGRect(x: x, y: y, width: rect.width * scaleX, height: rect.height * scaleY)
                    context.cgContext.fill(marked.insetBy(dx: -1, dy: -1))
                }
            }
        }
    }

    // MARK: Writing

    /// The changes as a Markdown note.
    static func report(_ comparison: EditionComparison) -> String {
        var lines: [String] = []
        lines.append("Comparing [[\(comparison.oldTitle)]] (old) with [[\(comparison.newTitle)]] (new). #editions")
        lines.append("")
        let counts = ChapterChangeKind.allCases.map { "\(comparison.count($0)) \($0.title.lowercased())" }
        lines.append("Chapters: " + counts.joined(separator: ", ") + ".")
        for kind in [ChapterChangeKind.added, .removed, .changed] {
            let items = comparison.changes.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            lines.append("")
            lines.append("## \(kind.title) chapters")
            for item in items {
                lines.append(contentsOf: reportLines(for: item, in: comparison))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func reportLines(for item: ChapterChange, in comparison: EditionComparison) -> [String] {
        switch item.kind {
        case .added:
            return ["- **\(item.title)** (new \(item.new?.pageLabel ?? ""))"]
        case .removed:
            return ["- **\(item.title)** (old \(item.old?.pageLabel ?? ""))"]
        case .same:
            return []
        case .changed:
            var lines = ["- **\(item.title)**: about \(item.percentChanged)% changed (\(item.pagesLabel))"]
            let sentences = comparison.sentenceChanges(of: item, limit: 3)
            for sentence in sentences.added { lines.append("  - Added: \(sentence.prefix(220))") }
            for sentence in sentences.removed { lines.append("  - Removed: \(sentence.prefix(220))") }
            return lines
        }
    }

    static func aiPrompt(for change: ChapterChange, in comparison: EditionComparison) -> String {
        let sentences = comparison.sentenceChanges(of: change, limit: 60)
        let added = sentences.added.map { "+ \($0)" }.joined(separator: "\n")
        let removed = sentences.removed.map { "- \($0)" }.joined(separator: "\n")
        return [
            "A book has a new edition. Explain what changed in the chapter \"\(change.title)\" between \"\(comparison.oldTitle)\" (old) and \"\(comparison.newTitle)\" (new), for a student who studied the old edition.",
            "Group the changes: new topics, removed topics, updated facts, numbers, guidelines or recommendations, and wording only. Say what matters for exams and practice. Use Markdown, short and clear. Keep the book's language.",
            "Sentences only in the new edition (+) and only in the old (−):",
            String(added.prefix(7000)),
            String(removed.prefix(5000)),
        ].joined(separator: "\n\n")
    }
}
