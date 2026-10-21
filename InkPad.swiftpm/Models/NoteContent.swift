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
    static let currentVersion = 1

    var version: Int
    var template: PageTemplate
    var pageCount: Int

    init(template: PageTemplate, pageCount: Int = 1) {
        self.version = Self.currentVersion
        self.template = template
        self.pageCount = pageCount
    }
}

/// Everything the editor needs to show and edit one note.
struct NoteContent {
    var metadata: NoteMetadata
    var drawing: PKDrawing
}
