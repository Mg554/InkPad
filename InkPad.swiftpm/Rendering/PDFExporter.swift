import PencilKit
import UIKit

/// Writes a note as a PDF: PDF pages stay vector, ink is added as an image.
@MainActor
enum PDFExporter {
    /// Ink resolution relative to canvas points.
    static let inkScale: CGFloat = 2

    static func export(_ content: NoteContent, title: String) throws -> URL {
        let background = content.makeBackground()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: title))
            .appendingPathExtension("pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: NoteBackground.templateExportSize))

        try renderer.writePDF(to: url) { context in
            for (index, pageRect) in background.layout.pageRects.enumerated() {
                autoreleasepool {
                    let pageSize = background.exportSize(ofPage: index)
                    context.beginPage(withBounds: CGRect(origin: .zero, size: pageSize), pageInfo: [:])
                    let cgContext = context.cgContext
                    let scale = pageSize.width / pageRect.width
                    cgContext.scaleBy(x: scale, y: scale)
                    cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
                    background.drawPage(at: index, in: cgContext)

                    guard content.drawing.bounds.intersects(pageRect) else { return }
                    var ink = UIImage()
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        ink = content.drawing.image(from: pageRect, scale: inkScale)
                    }
                    ink.draw(in: pageRect)
                }
            }
        }
        return url
    }

    private static func fileName(for title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Note" : cleaned
    }
}
