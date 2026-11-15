import Foundation

/// A comment pinned to a page, with its thread of replies. Comments are
/// page elements (`PageElement.Content.comment`), so they render, drag,
/// save, thumbnail and PDF-export through the element pipelines.
struct NoteComment: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var createdAt: Date
    /// Replies to this comment, oldest first. `nil` in older files.
    var replies: [NoteComment]?
    /// Settled: the pin turns grey and the thread is done. `nil` = open.
    var isResolved: Bool?

    init(text: String = "", replies: [NoteComment]? = nil, isResolved: Bool? = nil) {
        id = UUID()
        self.text = text
        createdAt = Date()
        self.replies = replies
        self.isResolved = isResolved
    }
}
