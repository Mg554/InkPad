import Foundation
import NaturalLanguage

/// A note's text, ready to become slides.
struct SlideSource: Sendable {
    let title: String
    /// Markdown for text notes; recognized writing for handwritten notes.
    let text: String
    let isMarkdown: Bool
}

/// A deck's words, before pictures and design are added.
struct DeckOutline: Sendable {
    var title: String
    var subtitle: String
    var slides: [Slide]
    var takeaways: [String]
}

/// Builds slides from notes on the iPad, without AI. Headings become slides
/// and lists their points; from loose text (such as recognized handwriting)
/// it keeps the sentences made of the notes' most frequent words, the way an
/// extractive summary does.
enum SlideOutliner {
    static func outline(_ sources: [SlideSource], format: DeckFormat, length: DeckLength, focus: String) -> DeckOutline {
        let words = DeckWords(for: sources.map { $0.text }.joined(separator: "\n"))
        var titles: [String] = []
        var sections: [Section] = []
        for source in sources {
            let parsed = source.isMarkdown
                ? parseMarkdown(source.text, title: source.title)
                : parsePlain(source.text, title: source.title)
            titles.append(parsed.title)
            sections += parsed.sections
        }

        let allText = sections.flatMap { $0.bullets + $0.sentences + $0.quotes }
        var frequencies = wordFrequencies(allText)
        // Sentences about what the deck should focus on rank first.
        for key in keys(in: focus) {
            frequencies[key, default: 0] += 8
        }

        let slides = contentSlides(from: sections, frequencies: frequencies, format: format, budget: length.contentSlides)
        let takeaways = rankedSentences(allText, frequencies: frequencies)
            .prefix(format == .presenter ? 3 : 4)
            .map { shortened($0, to: format.wordsPerBullet) }
        return DeckOutline(
            title: words.combinedTitle(titles),
            subtitle: words.subtitle(noteCount: sources.count),
            slides: slides,
            takeaways: takeaways
        )
    }

    /// At most `limit` words, ending in "…" when cut.
    static func shortened(_ text: String, to limit: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > limit else { return text }
        return words.prefix(limit).joined(separator: " ") + "…"
    }

    // MARK: Reading notes

    private struct Section {
        var title: String
        var bullets: [String] = []
        var sentences: [String] = []
        var quotes: [String] = []

        var isEmpty: Bool { bullets.isEmpty && sentences.isEmpty && quotes.isEmpty }
    }

    private struct ParsedSource {
        var title: String
        var sections: [Section]
    }

    private struct Heading {
        let level: Int
        let text: String
    }

    /// Headings start sections; lists, quotes and paragraphs fill them.
    private static func parseMarkdown(_ text: String, title: String) -> ParsedSource {
        var noteTitle = title
        var sections: [Section] = []
        var section = Section(title: title)
        var paragraph: [String] = []
        var sawHeading = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            section.sentences += sentences(in: paragraph.joined(separator: " "))
            paragraph = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if let header = heading(in: line) {
                flushParagraph()
                if header.level == 1, !sawHeading, section.isEmpty {
                    // The note's own title.
                    noteTitle = header.text
                    section.title = header.text
                } else {
                    if !section.isEmpty { sections.append(section) }
                    section = Section(title: header.text)
                }
                sawHeading = true
            } else if let item = listItem(in: line) {
                flushParagraph()
                section.bullets.append(item)
            } else if line.hasPrefix(">") {
                flushParagraph()
                let quote = clean(String(line.drop(while: { $0 == ">" || $0 == " " })))
                if !quote.isEmpty { section.quotes.append(quote) }
            } else if !isDecoration(line) {
                let cleaned = clean(line)
                if !cleaned.isEmpty { paragraph.append(cleaned) }
            }
        }
        flushParagraph()
        if !section.isEmpty { sections.append(section) }
        return ParsedSource(title: noteTitle, sections: sections)
    }

    /// Recognized handwriting: pages are separated by blank lines.
    private static func parsePlain(_ text: String, title: String) -> ParsedSource {
        var pieces: [String] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: .newlines)
                .map { clean($0) }
                .filter { $0.count > 1 }
            guard !lines.isEmpty else { continue }
            // Handwriting often has no punctuation; then each line stands alone.
            let punctuated = lines.filter { line in line.last.map { ".!?؟;:".contains($0) } ?? false }.count
            if punctuated * 3 >= lines.count {
                pieces += sentences(in: lines.joined(separator: " "))
            } else {
                pieces += lines
            }
        }
        return ParsedSource(title: title, sections: pieces.isEmpty ? [] : [Section(title: title, sentences: pieces)])
    }

    private static func heading(in line: String) -> Heading? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        let text = clean(String(line.dropFirst(level + 1)))
        return text.isEmpty ? nil : Heading(level: level, text: text)
    }

    private static let bulletPattern = try! NSRegularExpression(pattern: #"^(?:[-*+•]\s+(?:\[[ xX]\]\s+)?|\d{1,3}[.)]\s+)(.+)$"#)

    private static func listItem(in line: String) -> String? {
        guard let match = bulletPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        let item = clean(String(line[range]))
        return item.isEmpty ? nil : item
    }

    /// Dividers and lines of nothing but #tags.
    private static func isDecoration(_ line: String) -> Bool {
        if line.allSatisfy({ "-*_=".contains($0) || $0 == " " }) { return true }
        let words = line.split(separator: " ")
        return !words.isEmpty && words.allSatisfy { $0.hasPrefix("#") }
    }

    private static let aliasLinkPattern = try! NSRegularExpression(pattern: #"\[\[[^\[\]|]+\|([^\[\]]+)\]\]"#)
    private static let wikiLinkPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]|]+)\]\]"#)
    private static let markdownLinkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#)
    private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&/])#([\p{L}_][\p{L}\p{N}_/-]*)"#)
    private static let emphasisPattern = try! NSRegularExpression(pattern: #"\*\*|__|==|~~|`|\*"#)
    private static let spacePattern = try! NSRegularExpression(pattern: #"\s+"#)

    /// Plain text without Markdown marks; [[links]] keep their shown text.
    private static func clean(_ text: String) -> String {
        var result = text
        let replacements: [(NSRegularExpression, String)] = [
            (aliasLinkPattern, "$1"), (wikiLinkPattern, "$1"), (markdownLinkPattern, "$1"),
            (tagPattern, "$1"), (emphasisPattern, ""), (spacePattern, " "),
        ]
        for (pattern, template) in replacements {
            result = pattern.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 2 { result.append(sentence) }
            return true
        }
        return result
    }

    // MARK: Choosing what matters

    private struct Token {
        /// Lowercased, without the Arabic article, so forms count together.
        let key: String
        /// As written.
        let word: String
    }

    private static func tokens(in text: String) -> [Token] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [Token] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            let lowered = word.lowercased()
            guard !stopWords.contains(lowered) else { return true }
            var key = lowered
            if key.hasPrefix("ال"), key.count > 4 { key.removeFirst(2) }
            if key.count > 2, !stopWords.contains(key) {
                result.append(Token(key: key, word: word))
            }
            return true
        }
        return result
    }

    private static func keys(in text: String) -> [String] {
        tokens(in: text).map { $0.key }
    }

    private static func wordFrequencies(_ texts: [String]) -> [String: Int] {
        var frequencies: [String: Int] = [:]
        for text in texts {
            for key in keys(in: text) {
                frequencies[key, default: 0] += 1
            }
        }
        return frequencies
    }

    private static func score(_ sentence: String, frequencies: [String: Int]) -> Double {
        let found = keys(in: sentence)
        guard !found.isEmpty else { return 0 }
        let total = found.reduce(0) { $0 + (frequencies[$1] ?? 0) }
        return Double(total) / Double(found.count).squareRoot()
    }

    /// Most telling first, without repeats.
    private static func rankedSentences(_ sentences: [String], frequencies: [String: Int]) -> [String] {
        var seen: Set<String> = []
        let unique = sentences.filter { seen.insert($0).inserted }
        let scores = unique.map { score($0, frequencies: frequencies) }
        return unique.indices.sorted { scores[$0] > scores[$1] }.map { unique[$0] }
    }

    // MARK: Slides

    private static func contentSlides(from sections: [Section], frequencies: [String: Int], format: DeckFormat, budget: Int) -> [Slide] {
        let perSlide = format.bulletsPerSlide
        // Long stretches of loose text become several slides.
        var pieces: [Section] = []
        for section in sections {
            if section.bullets.isEmpty, section.sentences.count > perSlide * 2 {
                let parts = Int((Double(section.sentences.count) / Double(perSlide * 2)).rounded(.up))
                pieces += split(section, into: min(parts, budget), frequencies: frequencies)
            } else {
                pieces.append(section)
            }
        }
        // Too many: keep the weightiest, in their original order.
        if pieces.count > budget {
            let weights = pieces.map { section -> Double in
                rankedSentences(section.bullets + section.sentences, frequencies: frequencies)
                    .prefix(3)
                    .reduce(0.0) { $0 + score($1, frequencies: frequencies) }
            }
            let kept = Set(pieces.indices.sorted { weights[$0] > weights[$1] }.prefix(budget))
            let all = pieces
            pieces = all.indices.filter { kept.contains($0) }.map { all[$0] }
        }
        return pieces.compactMap { slide(for: $0, frequencies: frequencies, format: format) }
    }

    /// Splits loose text into `parts` slides in reading order, each titled
    /// by its key words.
    private static func split(_ section: Section, into parts: Int, frequencies: [String: Int]) -> [Section] {
        let lines = section.sentences
        let size = Int((Double(lines.count) / Double(max(parts, 1))).rounded(.up))
        guard size > 0 else { return [section] }
        return stride(from: 0, to: lines.count, by: size).map { start -> Section in
            let chunk = Array(lines[start..<min(start + size, lines.count)])
            return Section(title: keywordTitle(chunk, frequencies: frequencies) ?? section.title, sentences: chunk)
        }
    }

    private static func slide(for section: Section, frequencies: [String: Int], format: DeckFormat) -> Slide? {
        let limit = format.bulletsPerSlide
        var points = Array(section.bullets.prefix(limit))
        if points.count < limit {
            // Fill with the section's most telling sentences, in reading order.
            let best = Set(rankedSentences(section.sentences, frequencies: frequencies).prefix(limit - points.count))
            points += section.sentences.filter { best.contains($0) }
        }
        let bullets = points.prefix(limit).map { shortened($0, to: format.wordsPerBullet) }
        if bullets.isEmpty, let quote = section.quotes.first {
            return Slide(layout: .quote, title: shortened(quote, to: 40), speakerNotes: quote, symbol: "quote.opening")
        }
        guard !bullets.isEmpty else { return nil }
        let notes = section.sentences.prefix(4).joined(separator: " ")
        return Slide(
            layout: .bullets,
            title: shortened(section.title, to: 10),
            bullets: bullets,
            speakerNotes: notes.isEmpty ? bullets.joined(separator: ". ") : notes,
            symbol: SlideSymbols.symbol(for: ([section.title] + bullets).joined(separator: " "))
        )
    }

    /// The text's two most frequent key words, as a slide title.
    private static func keywordTitle(_ texts: [String], frequencies: [String: Int]) -> String? {
        var counts: [String: Int] = [:]
        var written: [String: String] = [:]
        for text in texts {
            for token in tokens(in: text) where token.key.count > 3 {
                counts[token.key, default: 0] += 1
                if written[token.key] == nil { written[token.key] = token.word }
            }
        }
        func weight(_ key: String) -> Int { (counts[key] ?? 0) * 10 + (frequencies[key] ?? 0) }
        let top = counts.keys.sorted { weight($0) != weight($1) ? weight($0) > weight($1) : $0 < $1 }.prefix(2)
        let words = top.compactMap { key in written[key].map { capitalized($0) } }
        guard !words.isEmpty else { return nil }
        let isArabic = words.contains { SlideSymbols.isArabic($0) }
        return words.joined(separator: isArabic ? " و" : " & ")
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + String(word.dropFirst())
    }

    private static let stopWords: Set<String> = [
        // English
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one",
        "our", "out", "has", "have", "his", "how", "its", "may", "now", "see", "who", "did", "get",
        "him", "let", "say", "she", "too", "use", "that", "with", "this", "from", "they", "will", "would",
        "there", "their", "what", "about", "which", "when", "make", "into", "than", "then", "them", "these",
        "some", "been", "more", "also", "such", "only", "other", "were", "your", "each", "most", "over",
        "very", "just", "because", "while", "where", "after", "before", "between", "through", "during",
        "without", "within", "should", "could", "must", "being", "does", "doing", "here", "those", "both",
        "same", "many", "much", "even", "well", "however", "therefore", "thus", "since", "upon", "onto",
        "yet", "via", "per", "etc", "like", "used", "using", "made", "way", "ways", "thing", "things",
        // Arabic
        "في", "من", "على", "إلى", "الى", "عن", "مع", "أن", "ان", "إن", "كان", "كانت", "يكون", "تكون",
        "هذا", "هذه", "ذلك", "تلك", "التي", "الذي", "الذين", "هو", "هي", "هم", "هن", "نحن", "أنا", "أنت",
        "كل", "بعض", "ما", "ماذا", "لا", "لم", "لن", "قد", "ثم", "أو", "او", "بل", "لكن", "حتى", "إذا",
        "اذا", "عند", "عندما", "بين", "بعد", "قبل", "حول", "غير", "أي", "كما", "مثل", "أيضا", "أيضاً",
        "فقط", "جدا", "جداً", "وهو", "وهي", "التى", "فيه", "فيها", "منه", "منها", "عليه", "عليها", "به",
        "بها", "له", "لها", "هناك", "هنا", "كيف", "لماذا", "متى", "أين", "يتم", "تم", "ذات", "وقد", "ولا",
        "وفي", "ومن", "وعلى", "يمكن", "أكثر", "اكثر",
    ]
}

/// Picks an SF Symbol for a slide from its words, in English or Arabic.
enum SlideSymbols {
    private static let table: [(symbol: String, words: [String])] = [
        ("lightbulb.fill", ["idea", "concept", "insight", "theory", "think", "فكرة", "مفهوم", "نظرية"]),
        ("chart.bar.fill", ["data", "statistic", "percent", "chart", "graph", "growth", "number", "بيانات", "إحصاء", "نسبة", "أرقام"]),
        ("clock.fill", ["time", "history", "timeline", "century", "year", "date", "era", "تاريخ", "زمن", "سنوات", "قرن"]),
        ("person.3.fill", ["people", "team", "society", "community", "population", "student", "user", "فريق", "مجتمع", "طلاب", "ناس", "سكان"]),
        ("target", ["goal", "objective", "target", "purpose", "mission", "aim", "هدف", "أهداف", "غاية"]),
        ("arrow.triangle.branch", ["process", "step", "method", "procedure", "workflow", "stage", "phase", "خطوات", "طريقة", "عملية", "مراحل"]),
        ("exclamationmark.triangle.fill", ["problem", "risk", "warning", "issue", "challenge", "danger", "error", "مشكلة", "خطر", "تحدي", "تحذير"]),
        ("questionmark.circle.fill", ["question", "quiz", "why", "سؤال", "أسئلة", "لماذا"]),
        ("dollarsign.circle.fill", ["money", "cost", "price", "budget", "finance", "economy", "market", "أموال", "تكلفة", "سعر", "ميزانية", "اقتصاد"]),
        ("flask.fill", ["science", "experiment", "chemistry", "biology", "physics", "cell", "molecule", "علم", "تجربة", "كيمياء", "أحياء", "فيزياء", "خلية"]),
        ("heart.fill", ["health", "medical", "medicine", "disease", "patient", "صحة", "صحي", "مرض", "علاج", "مستشفى"]),
        ("cpu.fill", ["technology", "computer", "software", "code", "digital", "algorithm", "network", "تقنية", "حاسوب", "برمجة", "خوارزمية"]),
        ("book.fill", ["book", "reading", "literature", "chapter", "story", "author", "كتاب", "قراءة", "أدب", "قصة"]),
        ("globe.americas.fill", ["world", "global", "country", "geography", "climate", "earth", "عالم", "دولة", "جغرافيا", "مناخ", "أرض"]),
        ("building.columns.fill", ["law", "rule", "policy", "government", "politic", "قانون", "قاعدة", "سياسة", "حكومة"]),
        ("function", ["math", "equation", "formula", "calcul", "algebra", "رياضيات", "معادلة"]),
        ("checkmark.seal.fill", ["summary", "conclusion", "result", "takeaway", "outcome", "خلاصة", "ملخص", "نتائج", "استنتاج"]),
    ]

    static func symbol(for text: String) -> String {
        let words = text.lowercased().split { !$0.isLetter }.map { stem(String($0)) }
        for entry in table where entry.words.contains(where: { keyword in words.contains { $0.hasPrefix(keyword) } }) {
            return entry.symbol
        }
        return "sparkles"
    }

    /// Arabic words without a leading "و" (and) or article, to match their keyword.
    private static func stem(_ word: String) -> String {
        var stemmed = word
        if stemmed.hasPrefix("و"), stemmed.count > 3 { stemmed.removeFirst() }
        if stemmed.hasPrefix("ال"), stemmed.count > 3 { stemmed.removeFirst(2) }
        return stemmed
    }

    /// For the one-word icon names Apple Intelligence is asked to choose from.
    static func symbol(forKeyword keyword: String) -> String {
        let key = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let entry = table.first(where: { $0.words.first == key }) {
            return entry.symbol
        }
        return symbol(for: key)
    }

    static func isArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }
}

/// The few words InkPad adds to a deck, in the notes' language.
struct DeckWords {
    let isArabic: Bool

    init(for text: String) {
        isArabic = NLLanguageRecognizer.dominantLanguage(for: String(text.prefix(3000))) == .arabic
    }

    var overview: String { isArabic ? "نظرة عامة" : "Overview" }
    var takeaways: String { isArabic ? "أهم النقاط" : "Key Takeaways" }

    func page(_ number: Int, of title: String) -> String {
        isArabic ? "\(title) · صفحة \(number)" : "\(title) · Page \(number)"
    }

    func subtitle(noteCount: Int, date: Date = Date()) -> String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        if isArabic {
            return noteCount > 1 ? "من \(noteCount) ملاحظات · \(day)" : "من ملاحظاتي · \(day)"
        }
        return noteCount > 1 ? "From \(noteCount) notes · \(day)" : "From my notes · \(day)"
    }

    func combinedTitle(_ titles: [String]) -> String {
        let named = titles.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = named.first else { return isArabic ? "عرض تقديمي" : "Slides" }
        guard named.count > 1 else { return first }
        return isArabic ? "\(first) و\(named.count - 1) أخرى" : "\(first) & \(named.count - 1) More"
    }
}
