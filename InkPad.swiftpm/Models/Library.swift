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

enum NoteKind: String, Codable {
    /// Ink on pages (the default; also every note from before kinds existed).
    case handwritten
    /// A Markdown text note with [[links]] and #tags, like Obsidian.
    case text
}

struct NoteSummary: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    /// `nil` means the note is unfiled.
    var folderID: UUID?
    let createdAt: Date
    var modifiedAt: Date
    /// `nil` means handwritten.
    var kind: NoteKind?
    /// Tags set from the library. Text notes also get the #tags in their text.
    var tags: [String]?

    var isText: Bool { kind == .text }
}

/// A reusable starting text for new text notes. `{{title}}`, `{{date}}`
/// and `{{time}}` are filled in when a note is created from it.
struct TextTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var body: String
    /// Built-in templates cannot be deleted.
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, body: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.body = body
        self.isBuiltIn = isBuiltIn
    }

    func filled(title: String, date: Date = Date()) -> String {
        body
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{date}}", with: date.formatted(date: .complete, time: .omitted))
            .replacingOccurrences(of: "{{time}}", with: date.formatted(date: .omitted, time: .shortened))
    }

    static let dailyNoteID = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000001")!

    static let builtIns: [TextTemplate] = [
        TextTemplate(id: dailyNoteID, name: "Daily Note", body: """
        # {{date}}

        ## Focus
        - 

        ## Notes
        

        ## Gratitude
        - 
        """, isBuiltIn: true),
        TextTemplate(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000002")!, name: "Meeting Notes", body: """
        # {{title}}
        {{date}} · {{time}}

        ## Attendees
        - 

        ## Agenda
        - 

        ## Decisions
        - 

        ## Action Items
        - [ ] 
        """, isBuiltIn: true),
        TextTemplate(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000003")!, name: "Study Notes", body: """
        # {{title}}
        #study

        ## Key Questions
        - 

        ## Notes
        

        ## Summary
        
        """, isBuiltIn: true),
        TextTemplate(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000004")!, name: "Book Notes", body: """
        # {{title}}
        #book

        **Author:** 
        **Started:** {{date}}

        ## Highlights
        > 

        ## Thoughts
        
        """, isBuiltIn: true),
    ]
}

/// The persisted index of folders and notes (`library.json`).
struct LibraryIndex: Codable {
    /// Version 2 added folder `parentID` and `color`; version 3 added note
    /// `kind` and `tags`, and `textTemplates`. Older files still decode unchanged.
    static let currentVersion = 3

    var version: Int
    var folders: [Folder]
    var notes: [NoteSummary]
    /// The user's own templates (built-ins are not stored).
    var textTemplates: [TextTemplate]?
}

/// What the library sidebar can select.
enum LibraryScope: Hashable {
    case allNotes
    case unfiled
    case folder(UUID)
    /// The workspace pages; they hold no notes.
    case planner
    case expenses
    case mindMaps
    /// Slide decks made from notes.
    case slides
    /// Study with AI: chat, flashcards, quizzes.
    case study
    /// The Flowmodoro focus timer and its tasks.
    case flowmodoro
    /// Notes with this tag (without the #).
    case tag(String)
    /// The graph of notes and their links.
    case graph
}

/// A folder positioned in the folder tree, for sidebars and menus.
struct FolderRow: Identifiable {
    let folder: Folder
    let depth: Int
    let hasChildren: Bool

    var id: UUID { folder.id }
}
