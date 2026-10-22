import Foundation

/// Reads Obsidian-style [[links]] and #tags out of Markdown text. The only
/// place that interprets them, so links, backlinks, tags and the graph agree.
enum NoteLinks {
    struct Link: Equatable {
        /// The linked note's title, as written.
        let title: String
        /// Text shown instead of the title (`[[Title|shown text]]`).
        let alias: String?
    }

    private static let linkPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]|]+)(?:\|([^\[\]]*))?\]\]"#)
    private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&/#])#([\p{L}_][\p{L}\p{N}_/-]*)"#)

    static func links(in text: String) -> [Link] {
        let range = NSRange(text.startIndex..., in: text)
        return linkPattern.matches(in: text, range: range).compactMap { match in
            guard let titleRange = Range(match.range(at: 1), in: text) else { return nil }
            let title = text[titleRange].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            let alias = Range(match.range(at: 2), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
            return Link(title: title, alias: alias?.isEmpty == true ? nil : alias)
        }
    }

    /// Tags without the #, in order of first appearance. Text inside
    /// [[links]] is not read as tags.
    static func tags(in text: String) -> [String] {
        let withoutLinks = linkPattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " "
        )
        let range = NSRange(withoutLinks.startIndex..., in: withoutLinks)
        var seen: Set<String> = []
        return tagPattern.matches(in: withoutLinks, range: range).compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: withoutLinks) else { return nil }
            let tag = String(withoutLinks[tagRange])
            return seen.insert(key(tag)).inserted ? tag : nil
        }
    }

    /// How titles and tags are compared: case- and accent-insensitive.
    static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Parses a comma or space separated tag list typed by the user.
    static func parseTagList(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text
            .components(separatedBy: CharacterSet(charactersIn: ", "))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }
}
