import Foundation
import PencilKit
import CoreGraphics

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

/// A colored bookmark on a page of a note (a book).
struct NoteBookmark: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Layout page, zero-based.
    var page: Int
    var title: String
    var color: FolderColor
}

/// Where a chapter's notes start in a notebook.
struct NotebookChapter: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// The chapter's first PDF page in the book (zero-based).
    var bookPage: Int
    /// The notebook page (zero-based).
    var page: Int
}

/// The book pages (PDF, zero-based) a notebook page was written beside.
struct NotebookPageLink: Codable, Equatable {
    var page: Int
    var bookPages: [Int]
}

/// A paper page's size in PDF points (1/72 inch). Only its shape shows
/// on screen: every page is drawn the same width.
struct PaperSize: Codable, Equatable, Hashable {
    var width: Double
    var height: Double

    /// The size of plain `.paper` pages (A4 portrait).
    static let standard = PaperSize(width: 595.28, height: 841.89)

    var isLandscape: Bool { width > height }

    var swapped: PaperSize { PaperSize(width: height, height: width) }

    /// Screen height for a page `PageLayout.pageWidth` wide.
    var layoutHeight: CGFloat {
        guard width > 0, height > 0 else { return PageLayout.templatePageSize.height }
        let ratio: Double = height / width
        return PageLayout.pageWidth * CGFloat(min(max(ratio, 0.2), 5))
    }
}

/// Ready-made page sizes; `custom` takes any width and height.
enum PaperPreset: String, CaseIterable, Identifiable {
    case a4, letter, a5, square, wide, screen, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .a5: "A5"
        case .square: "Square"
        case .wide: "Wide (16:9)"
        case .screen: "iPad Screen"
        case .custom: "Custom"
        }
    }

    /// Portrait size (custom has none).
    var size: PaperSize? {
        switch self {
        case .a4: PaperSize.standard
        case .letter: PaperSize(width: 612, height: 792)
        case .a5: PaperSize(width: 419.53, height: 595.28)
        case .square: PaperSize(width: 595.28, height: 595.28)
        case .wide: PaperSize(width: 595.28, height: 1058.27)
        case .screen: PaperSize(width: 595.28, height: 793.71)
        case .custom: nil
        }
    }

    /// The preset a size matches, in either orientation.
    static func matching(_ size: PaperSize) -> PaperPreset {
        for preset in allCases {
            guard let base = preset.size else { continue }
            if abs(base.width - size.width) < 1, abs(base.height - size.height) < 1 { return preset }
            if abs(base.height - size.width) < 1, abs(base.width - size.height) < 1 { return preset }
        }
        return .custom
    }
}

/// What one page shows underneath the ink.
enum PageSource: Codable, Equatable {
    /// A page of the note's PDF (zero-based).
    case pdf(Int)
    /// Template paper, A4.
    case paper
    /// Template paper of another size.
    case sizedPaper(PaperSize)

    var isPaper: Bool {
        switch self {
        case .pdf: false
        case .paper, .sizedPaper: true
        }
    }

    /// The paper size, or nil for a PDF page.
    var paperSize: PaperSize? {
        switch self {
        case .pdf: nil
        case .paper: PaperSize.standard
        case let .sizedPaper(size): size
        }
    }

    /// Paper of this size (plain `.paper` for A4, which older versions read).
    static func paper(of size: PaperSize) -> PageSource {
        size == PaperSize.standard ? .paper : .sizedPaper(size)
    }
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
    /// Bookmarks on pages (books).
    var bookmarks: [NoteBookmark]?
    /// The page last read, and the furthest page reached (layout pages).
    var readingPage: Int?
    var furthestPage: Int?
    /// A book: the notebook written beside it (a paper note).
    var notebookID: UUID?
    /// A notebook: the book it belongs to, the page where each chapter's
    /// notes start, and the book pages each page was written beside.
    var notebookFor: UUID?
    var notebookChapters: [NotebookChapter]?
    var bookPageLinks: [NotebookPageLink]?

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
