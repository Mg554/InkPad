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
    /// AI Firewall: notes in this folder and its subfolders are never sent
    /// to an AI service.
    var hiddenFromAI: Bool?
    /// AI Firewall: only Apple Intelligence on the iPad may read them.
    var aiOnDeviceOnly: Bool?

    var aiAccess: AIAccess {
        hiddenFromAI == true ? .never : aiOnDeviceOnly == true ? .onDeviceOnly : .allowed
    }

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), parentID: UUID? = nil, color: FolderColor? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.parentID = parentID
        self.color = color
    }
}

/// AI Firewall: who may read a note or a folder's notes. Stricter levels
/// win: a note in a "Never" folder is never sent, whatever its own level.
enum AIAccess: Int, CaseIterable, Identifiable, Comparable {
    /// Any AI service the user connected.
    case allowed
    /// Only Apple Intelligence on this iPad; nothing leaves the device.
    case onDeviceOnly
    /// No AI at all.
    case never

    var id: Self { self }

    static func < (lhs: AIAccess, rhs: AIAccess) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .allowed: "Allowed"
        case .onDeviceOnly: "This iPad Only"
        case .never: "Never"
        }
    }

    var detail: String {
        switch self {
        case .allowed: "Any AI service you connected may read it."
        case .onDeviceOnly: "Only Apple Intelligence on this iPad; never sent online."
        case .never: "Never read by any AI."
        }
    }

    var systemImage: String {
        switch self {
        case .allowed: "lock.open"
        case .onDeviceOnly: "ipad"
        case .never: "lock.shield.fill"
        }
    }

    /// Whether an AI running on the device (`onDevice`) or online may read it.
    func permits(onDevice: Bool) -> Bool {
        switch self {
        case .allowed: true
        case .onDeviceOnly: onDevice
        case .never: false
        }
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
    /// Set while the note is in Recently Deleted.
    var deletedAt: Date?
    /// AI Firewall: never sent to an AI service.
    var hiddenFromAI: Bool?
    /// AI Firewall: only Apple Intelligence on the iPad may read it.
    var aiOnDeviceOnly: Bool?
    /// Starred: listed under Favorites.
    var isFavorite: Bool?
    /// When it was pinned; pinned notes come first in every list.
    var pinnedAt: Date?
    /// A cover shown instead of the first page.
    var cover: NoteCover?
    /// Read from the note's files (see `NoteFacts`); `nil` until known.
    var hasAudio: Bool?
    var hasPDF: Bool?
    var pageCount: Int?

    var aiAccess: AIAccess {
        hiddenFromAI == true ? .never : aiOnDeviceOnly == true ? .onDeviceOnly : .allowed
    }

    var isText: Bool { kind == .text }
    var favorite: Bool { isFavorite == true }
    var isPinned: Bool { pinnedAt != nil }
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
    /// `kind` and `tags`, and `textTemplates`; version 4 added `trash`
    /// (Recently Deleted) and `hiddenFromAI`/`aiOnDeviceOnly` on notes and folders (AI
    /// Firewall). Older files still decode unchanged.
    static let currentVersion = 4

    var version: Int
    var folders: [Folder]
    var notes: [NoteSummary]
    /// The user's own templates (built-ins are not stored).
    var textTemplates: [TextTemplate]?
    /// Deleted notes, kept for `LibraryStore.trashDays` days.
    var trash: [NoteSummary]?
    /// Custom Order, per list (see `LibraryScope.orderKey`).
    var customOrders: [String: [UUID]]?
    /// The owner's smart collections.
    var collections: [SmartCollection]?
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
    /// Apple Reminders, shown and edited in InkPad.
    case reminders
    /// Notes with this tag (without the #).
    case tag(String)
    /// The graph of notes and their links.
    case graph
    /// PDF tools (merge, split, pages to a note...).
    case pdfTools
    /// Knowledge GPS: maps of what to learn.
    case gps
    /// Starred notes.
    case favorites
    /// A collection that fills itself.
    case builtIn(BuiltInCollection)
    /// One of the owner's smart collections.
    case collection(UUID)
}

/// A folder positioned in the folder tree, for sidebars and menus.
struct FolderRow: Identifiable {
    let folder: Folder
    let depth: Int
    let hasChildren: Bool

    var id: UUID { folder.id }
}
