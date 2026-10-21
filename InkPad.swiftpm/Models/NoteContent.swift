import Foundation
import PencilKit

enum PageTemplate: String, Codable, CaseIterable, Identifiable {
    case blank
    case lined
    case grid
    case dotted

    var id: Self { self }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .lined: "Lined"
        case .grid: "Grid"
        case .dotted: "Dotted"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .lined: "text.justify"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        }
    }
}

/// Per-note settings stored next to the drawing (`note.json`).
struct NoteMetadata: Codable, Equatable {
    /// Version 2 added `pdfFile`. Version 1 files still decode unchanged.
    static let currentVersion = 2

    var version: Int
    /// Paper for pages that are not PDF pages.
    var template: PageTemplate
    /// Number of template pages. In a PDF note they follow the PDF's pages.
    var pageCount: Int
    /// File name of the imported PDF inside the note's folder, if any.
    var pdfFile: String?

    init(template: PageTemplate, pageCount: Int = 1, pdfFile: String? = nil) {
        self.version = Self.currentVersion
        self.template = template
        self.pageCount = pageCount
        self.pdfFile = pdfFile
    }
}

/// Everything the editor needs to show and edit one note.
struct NoteContent {
    var metadata: NoteMetadata
    var drawing: PKDrawing
    /// The opened PDF named by `metadata.pdfFile`.
    let pdf: PDFBackground?

    func makeBackground() -> NoteBackground {
        NoteBackground(template: metadata.template, templatePageCount: metadata.pageCount, pdf: pdf)
    }
}
