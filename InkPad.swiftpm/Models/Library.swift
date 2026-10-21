import Foundation

struct Folder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct NoteSummary: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    /// `nil` means the note is unfiled.
    var folderID: UUID?
    let createdAt: Date
    var modifiedAt: Date
}

/// The persisted index of folders and notes (`library.json`).
struct LibraryIndex: Codable {
    static let currentVersion = 1

    var version: Int
    var folders: [Folder]
    var notes: [NoteSummary]
}

/// What the library sidebar can select.
enum LibraryScope: Hashable {
    case allNotes
    case unfiled
    case folder(UUID)
}
