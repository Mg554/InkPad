import Foundation
import PencilKit

enum PageTemplate: String, Codable, CaseIterable, Identifiable {
    case blank
    case lined
    case grid
    case dotted
    case hexagon
    case cornell
    case collegeRule
    case manuscript
    case threeColumn
    case twoColumn

    enum Section: String, CaseIterable, Identifiable {
        case basic = "Basic Templates"
        case notepads = "Notepads"
        var id: Self { self }
    }

    var id: Self { self }

    var section: Section {
        switch self {
        case .blank, .lined, .grid, .dotted: .basic
        default: .notepads
        }
    }

    var title: String {
        switch self {
        case .blank: "Plain"
        case .lined: "Lined"
        case .grid: "Grid"
        case .dotted: "Dot"
        case .hexagon: "Hexagonal Grid"
        case .cornell: "Cornell Note"
        case .collegeRule: "College Rule"
        case .manuscript: "Manuscript"
        case .threeColumn: "Three Column"
        case .twoColumn: "Two Column"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .lined, .collegeRule, .manuscript: "text.justify"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        case .hexagon: "hexagon"
        case .cornell: "rectangle.split.2x1"
        case .threeColumn, .twoColumn: "rectangle.split.3x1"
        }
    }
}

enum PaperColor: String, Codable, CaseIterable, Identifiable {
    case white, ivory, sand, mist, charcoal, black

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .white: return (red: 1, green: 1, blue: 1)
        case .ivory: return (red: 0.99, green: 0.98, blue: 0.93)
        case .sand: return (red: 0.94, green: 0.89, blue: 0.78)
        case .mist: return (red: 0.87, green: 0.89, blue: 0.91)
        case .charcoal: return (red: 0.25, green: 0.26, blue: 0.28)
        case .black: return (red: 0.09, green: 0.09, blue: 0.10)
        }
    }

    var isDark: Bool { self == .charcoal || self == .black }
}

/// What one page shows underneath the ink.
enum PageSource: Codable, Equatable {
    /// A page of the note's PDF (zero-based).
    case pdf(Int)
    /// Template paper.
    case paper
}

/// Per-note settings stored next to the drawing (`note.json`).
struct NoteMetadata: Codable, Equatable {
    /// Version 2 added `pdfFile`; version 3 added `paperColor` and `elements`;
    /// version 4 added `pages`; version 5 added `recordings`. Older files
    /// still decode unchanged.
    static let currentVersion = 5

    var version: Int
    /// Paper for pages that are not PDF pages.
    var template: PageTemplate
    /// Number of template pages. Only used when `pages` is `nil` (older
    /// notes), where they follow the PDF's pages.
    var pageCount: Int
    /// File name of the imported PDF inside the note's folder, if any.
    var pdfFile: String?
    /// `nil` means white.
    var paperColor: PaperColor?
    /// Text boxes and images, in canvas coordinates.
    var elements: [PageElement]?
    /// The pages in order. `nil` means the PDF's pages followed by `pageCount` paper pages.
    var pages: [PageSource]?
    /// Audio recorded with the note, oldest first.
    var recordings: [AudioRecording]?

    func resolvedPages(pdfPageCount: Int) -> [PageSource] {
        pages ?? (0..<pdfPageCount).map { PageSource.pdf($0) } + Array(repeating: .paper, count: max(pageCount, 0))
    }

    init(template: PageTemplate, pageCount: Int = 1, pdfFile: String? = nil) {
        self.version = Self.currentVersion
        self.template = template
        self.pageCount = pageCount
        self.pdfFile = pdfFile
    }
}

/// Everything the editor needs to show and edit one note.
///
/// Sendable so it can be handed to the background writer and renderers: it is
/// a value, and its PDF is only ever read (drawing a CGPDFDocument is thread-safe).
struct NoteContent: @unchecked Sendable {
    var metadata: NoteMetadata
    var drawing: PKDrawing
    /// The opened PDF named by `metadata.pdfFile`.
    let pdf: PDFBackground?
    /// The note's folder; image elements live in its `images` subfolder.
    let directory: URL

    var imageDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    var audioDirectory: URL { directory.appendingPathComponent("audio", isDirectory: true) }

    func makeBackground() -> NoteBackground {
        NoteBackground(
            template: metadata.template,
            paper: metadata.paperColor ?? .white,
            pages: metadata.resolvedPages(pdfPageCount: pdf?.pageCount ?? 0),
            pdf: pdf
        )
    }
}
