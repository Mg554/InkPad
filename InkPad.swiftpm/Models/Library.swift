import Foundation

enum FolderColor: String, Codable, CaseIterable, Identifiable {
    case gray, red, orange, yellow, green, teal, blue, purple, pink

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct Folder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    /// `nil` means a top-level folder.
    var parentID: UUID?
    /// `nil` means the default color.
    var color: FolderColor?

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), parentID: UUID? = nil, color: FolderColor? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.parentID = parentID
        self.color = color
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
    /// Version 2 added folder `parentID` and `color`. Version 1 files still decode unchanged.
    static let currentVersion = 2

    var version: Int
    var folders: [Folder]
    var notes: [NoteSummary]
}

/// What the library sidebar can select.
enum LibraryScope: Hashable {
    case allNotes
    case unfiled
    case folder(UUID)
    /// The workspace pages; they hold no notes.
    case planner
    case expenses
}

/// A folder positioned in the folder tree, for sidebars and menus.
struct FolderRow: Identifiable {
    let folder: Folder
    let depth: Int
    let hasChildren: Bool

    var id: UUID { folder.id }
}
