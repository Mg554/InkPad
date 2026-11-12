import Foundation

/// How a list of notes is ordered.
enum NoteSort: String, CaseIterable, Identifiable {
    case edited, created, name, pages, custom

    static let storageKey = "librarySort"

    var id: Self { self }

    var title: String {
        switch self {
        case .edited: "Last Edited"
        case .created: "Date Created"
        case .name: "Name"
        case .pages: "Pages"
        case .custom: "Custom Order"
        }
    }

    var systemImage: String {
        switch self {
        case .edited: "clock"
        case .created: "calendar"
        case .name: "textformat"
        case .pages: "doc.on.doc"
        case .custom: "hand.draw"
        }
    }
}

/// Cards or detailed rows.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list

    static let storageKey = "libraryLayout"

    var id: Self { self }
}

/// An optional cover shown on a note's card instead of its first page.
struct NoteCover: Codable, Hashable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case solid, gradient, stripes, dots, grid

        var id: Self { self }

        var title: String {
            switch self {
            case .solid: "Solid"
            case .gradient: "Gradient"
            case .stripes: "Stripes"
            case .dots: "Dots"
            case .grid: "Grid"
            }
        }
    }

    enum TitleFont: String, Codable, CaseIterable, Identifiable {
        case rounded, serif, mono, handwritten

        var id: Self { self }

        var title: String {
            switch self {
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .mono: "Mono"
            case .handwritten: "Handwritten"
            }
        }
    }

    var style: Style
    var color: FolderColor
    /// The gradient's second color.
    var secondColor: FolderColor
    var font: TitleFont

    static let standard = NoteCover(style: .gradient, color: .blue, secondColor: .purple, font: .rounded)

    init(style: Style, color: FolderColor, secondColor: FolderColor, font: TitleFont) {
        self.style = style
        self.color = color
        self.secondColor = secondColor
        self.font = font
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = container.value(.style, or: Style.gradient)
        color = container.value(.color, or: FolderColor.blue)
        secondColor = container.value(.secondColor, or: FolderColor.purple)
        font = container.value(.font, or: TitleFont.rounded)
    }
}

/// Collections that fill themselves.
enum BuiltInCollection: String, CaseIterable, Identifiable, Hashable {
    case recent, pdfs, audio, tasks, untitled

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recently Edited"
        case .pdfs: "PDFs"
        case .audio: "With Audio"
        case .tasks: "Unfinished Tasks"
        case .untitled: "Untitled"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock.arrow.circlepath"
        case .pdfs: "doc.richtext"
        case .audio: "waveform"
        case .tasks: "checklist.unchecked"
        case .untitled: "questionmark.square.dashed"
        }
    }
}

/// A collection made from the owner's own rules: every rule that is set
/// must match.
struct SmartCollection: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case any, handwritten, pdf, text

        var id: Self { self }

        var title: String {
            switch self {
            case .any: "Any Kind"
            case .handwritten: "Handwritten"
            case .pdf: "PDF"
            case .text: "Text"
            }
        }
    }

    let id: UUID
    var name: String
    var kind: Kind
    /// A tag without the #.
    var tag: String?
    /// Edited in the last this many days.
    var editedWithinDays: Int?
    var needsAudio: Bool
    var needsOpenTasks: Bool
    var onlyFavorites: Bool

    init(name: String) {
        id = UUID()
        self.name = name
        kind = .any
        tag = nil
        editedWithinDays = nil
        needsAudio = false
        needsOpenTasks = false
        onlyFavorites = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = container.value(.name, or: "Collection")
        kind = container.value(.kind, or: Kind.any)
        tag = container.value(.tag, or: nil)
        editedWithinDays = container.value(.editedWithinDays, or: nil)
        needsAudio = container.value(.needsAudio, or: false)
        needsOpenTasks = container.value(.needsOpenTasks, or: false)
        onlyFavorites = container.value(.onlyFavorites, or: false)
    }
}

/// Facts about a note read from its files, for collections and the list view.
struct NoteFacts: Equatable, Sendable {
    var hasAudio: Bool
    var hasPDF: Bool
    var pageCount: Int
}

extension LibraryScope {
    /// The key a custom order is kept under.
    var orderKey: String {
        switch self {
        case .allNotes: "all"
        case .unfiled: "unfiled"
        case .favorites: "favorites"
        case let .folder(id): "folder-" + id.uuidString
        case let .tag(tag): "tag-" + NoteLinks.key(tag)
        case let .builtIn(collection): "builtin-" + collection.rawValue
        case let .collection(id): "collection-" + id.uuidString
        default: "other"
        }
    }
}
