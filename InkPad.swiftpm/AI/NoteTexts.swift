import Foundation

/// A note's words, for AI study.
struct StudySource: Sendable {
    let id: UUID
    let title: String
    let text: String
}

/// Gets the text of notes: Markdown as written, and for handwritten and PDF
/// notes the writing recognized on the iPad (kept in `text.json`, so each
/// note is only read again after it changes).
@MainActor
enum NoteTexts {
    static let maxPages = 40

    /// - Parameters:
    ///   - live: the note as it is in an open editor.
    ///   - refresh: read the handwriting again even if a current copy is kept.
    static func text(
        of id: UUID,
        store: LibraryStore,
        live: NoteContent? = nil,
        refresh: Bool = false,
        progress: ((String) -> Void)? = nil
    ) async -> String {
        guard let summary = store.note(id) else { return "" }
        if summary.isText {
            return (try? store.loadMarkdown(for: id)) ?? ""
        }
        if !refresh, let cached = store.cachedRecognizedText(for: id) {
            return cached
        }
        guard let content = live ?? (try? store.loadContent(for: id)) else { return "" }
        let background = content.makeBackground()
        let count = min(background.layout.pageRects.count, maxPages)
        var pages: [String] = []
        for index in 0..<count {
            progress?("Reading \(summary.title): page \(index + 1) of \(count)…")
            let page = await Task.detached(priority: .utility) {
                NoteReader.read(page: index, of: content, background: background, wantsImage: false)
            }.value
            if !page.text.isEmpty { pages.append(page.text) }
        }
        let text = pages.joined(separator: "\n\n")
        store.saveRecognizedText(text, for: id)
        return text
    }

    /// The text of several notes (every note when `ids` is empty).
    static func sources(
        _ ids: [UUID],
        store: LibraryStore,
        live: [UUID: NoteContent] = [:],
        progress: ((String) -> Void)? = nil
    ) async -> [StudySource] {
        let chosen = ids.isEmpty ? store.notes(in: .allNotes).map(\.id) : ids
        var result: [StudySource] = []
        for id in chosen {
            guard let note = store.note(id) else { continue }
            let words = await text(of: id, store: store, live: live[id], progress: progress)
            if !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(StudySource(id: id, title: note.title, text: words))
            }
        }
        return result
    }

    /// The notes as one block of text within `budget` characters. When they
    /// don't all fit, the notes sharing most words with `question` come first.
    static func context(_ sources: [StudySource], budget: Int, question: String = "") -> String {
        var ordered = sources
        let total = sources.reduce(0) { $0 + $1.text.count }
        if total > budget, !question.isEmpty {
            let words = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map { String($0) }.filter { $0.count > 2 })
            func score(_ source: StudySource) -> Int {
                let text = (source.title + " " + source.text).lowercased()
                return words.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            }
            ordered.sort { score($0) > score($1) }
        }
        var parts: [String] = []
        var used = 0
        for source in ordered {
            guard used < budget else { break }
            let room = budget - used
            let body = source.text.count > room ? String(source.text.prefix(room)) + "\n[…]" : source.text
            parts.append("=== Note: \(source.title) ===\n\(body)")
            used += body.count
        }
        return parts.joined(separator: "\n\n")
    }
}
