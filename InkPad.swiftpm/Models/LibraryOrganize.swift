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

/// How the notes are shown: cards, small icons, rows, or as shapes.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, icons, compact, list, bubbles, circle, tree, shelf, timeline

    static let storageKey = "libraryLayout"

    var id: Self { self }

    var title: String {
        switch self {
        case .grid: "Cards"
        case .icons: "Small Icons"
        case .compact: "Compact List"
        case .list: "Detailed List"
        case .bubbles: "Bubbles"
        case .circle: "Circle"
        case .tree: "Tree"
        case .shelf: "Bookshelf"
        case .timeline: "Timeline"
        }
    }

    /// Shapes show every note together (no pinned row).
    var isShape: Bool {
        switch self {
        case .bubbles, .circle, .tree, .shelf, .timeline: true
        default: false
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .icons: "square.grid.4x3.fill"
        case .compact: "list.dash"
        case .list: "list.bullet.rectangle"
        case .bubbles: "circle.grid.cross"
        case .circle: "circle.dashed"
        case .tree: "list.bullet.indent"
        case .shelf: "books.vertical"
        case .timeline: "calendar.day.timeline.left"
        }
    }
}

/// An optional cover shown on a note's card instead of its first page:
/// a material (color, gradient, pattern, old leather, cloth...), the title
/// in a chosen font, size, place and color, and decorations.
struct NoteCover: Codable, Hashable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case solid, gradient, stripes, dots, grid, leather, cloth, wood, marble, spiral, kraft

        var id: Self { self }

        var title: String {
            switch self {
            case .solid: "Solid"
            case .gradient: "Gradient"
            case .stripes: "Stripes"
            case .dots: "Dots"
            case .grid: "Grid"
            case .leather: "Old Leather"
            case .cloth: "Cloth"
            case .wood: "Wood"
            case .marble: "Marble"
            case .spiral: "Spiral Notebook"
            case .kraft: "Kraft Paper"
            }
        }

        /// Materials pick their own colors; the color only tints them.
        var isMaterial: Bool {
            switch self {
            case .leather, .wood, .marble, .kraft: true
            default: false
            }
        }

        var usesSecondColor: Bool { self == .gradient || self == .grid || self == .marble }
    }

    enum TitleFont: String, Codable, CaseIterable, Identifiable {
        case rounded, serif, mono, handwritten
        case verdana, georgia, avenir, futura, didot, baskerville, typewriter, marker, script, chalk
        case naskh, farah, mishafi, kufi

        var id: Self { self }

        var title: String {
            switch self {
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .mono: "Mono"
            case .handwritten: "Handwritten"
            case .verdana: "Verdana"
            case .georgia: "Georgia"
            case .avenir: "Avenir"
            case .futura: "Futura"
            case .didot: "Didot"
            case .baskerville: "Baskerville"
            case .typewriter: "Typewriter"
            case .marker: "Marker"
            case .script: "Script"
            case .chalk: "Chalk"
            case .naskh: "Naskh (Arabic)"
            case .farah: "Farah (Arabic)"
            case .mishafi: "Mishafi (Arabic)"
            case .kufi: "Kufi (Arabic)"
            }
        }

        var isArabic: Bool {
            switch self {
            case .naskh, .farah, .mishafi, .kufi: true
            default: false
            }
        }

        /// The iPad font family (nil for the system designs).
        var family: String? {
            switch self {
            case .rounded, .serif, .mono: nil
            case .handwritten: "Noteworthy"
            case .verdana: "Verdana"
            case .georgia: "Georgia"
            case .avenir: "Avenir Next"
            case .futura: "Futura"
            case .didot: "Didot"
            case .baskerville: "Baskerville"
            case .typewriter: "American Typewriter"
            case .marker: "Marker Felt"
            case .script: "Snell Roundhand"
            case .chalk: "Chalkduster"
            case .naskh: "Geeza Pro"
            case .farah: "Farah"
            case .mishafi: "Diwan Mishafi"
            case .kufi: "Kufi Standard GK"
            }
        }
    }

    enum TitlePlace: String, Codable, CaseIterable, Identifiable {
        case top, center, bottom
        var id: Self { self }
        var title: String {
            switch self {
            case .top: "Top"
            case .center: "Middle"
            case .bottom: "Bottom"
            }
        }
    }

    enum TitleInk: String, Codable, CaseIterable, Identifiable {
        case white, gold, silver, black, cream
        var id: Self { self }
        var title: String {
            switch self {
            case .white: "White"
            case .gold: "Gold"
            case .silver: "Silver"
            case .black: "Black"
            case .cream: "Cream"
            }
        }
    }

    enum Frame: String, Codable, CaseIterable, Identifiable {
        case none, line, double, ornate
        var id: Self { self }
        var title: String {
            switch self {
            case .none: "None"
            case .line: "Line"
            case .double: "Double"
            case .ornate: "Ornate"
            }
        }
    }

    var style: Style
    var color: FolderColor
    /// The gradient's second color.
    var secondColor: FolderColor
    var font: TitleFont
    var titleScale: Double = 1
    var titlePlace: TitlePlace = .center
    var titleInk: TitleInk = .white
    /// The title sits on a label plate.
    var titlePlate: Bool = false
    var frame: Frame = .none
    /// An SF Symbol name or an emoji.
    var emblem: String?
    var metalCorners: Bool = false
    var ribbon: Bool = false
    var band: Bool = false

    static let standard = NoteCover(style: .gradient, color: .blue, secondColor: .purple, font: .rounded)

    /// The old leather book, ready-made.
    static let leatherBook: NoteCover = {
        var cover = NoteCover(style: .leather, color: .orange, secondColor: .red, font: .baskerville)
        cover.titleInk = .gold
        cover.frame = .ornate
        cover.metalCorners = true
        cover.ribbon = true
        cover.titlePlace = .center
        return cover
    }()

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
        titleScale = container.value(.titleScale, or: 1.0)
        titlePlace = container.value(.titlePlace, or: TitlePlace.center)
        titleInk = container.value(.titleInk, or: TitleInk.white)
        titlePlate = container.value(.titlePlate, or: false)
        frame = container.value(.frame, or: Frame.none)
        emblem = container.value(.emblem, or: nil)
        metalCorners = container.value(.metalCorners, or: false)
        ribbon = container.value(.ribbon, or: false)
        band = container.value(.band, or: false)
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
