import PencilKit
import UIKit

/// Renders small page previews for the library grid and the page overview.
/// Safe to call off the main thread.
enum ThumbnailRenderer {
    static let libraryScale: CGFloat = 0.3

    /// First-page preview stored with the note.
    static func pngData(for content: NoteContent) -> Data? {
        let background = content.makeBackground()
        guard !background.layout.pageRects.isEmpty else { return nil }
        return image(
            ofPage: 0,
            drawing: content.drawing,
            elements: content.metadata.elements ?? [],
            imageDirectory: content.imageDirectory,
            background: background,
            scale: libraryScale
        ).pngData()
    }

    static func image(
        ofPage index: Int,
        drawing: PKDrawing,
        elements: [PageElement],
        imageDirectory: URL,
        background: NoteBackground,
        scale: CGFloat
    ) -> UIImage {
        let pageRect = background.layout.pageRects[index]

        // Render ink with light-mode colors so it matches the paper.
        var ink: UIImage?
        if drawing.bounds.intersects(pageRect) {
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                ink = drawing.image(from: pageRect, scale: max(scale * 2, 0.5))
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
            background.drawPage(at: index, in: context.cgContext)
            ElementRenderer.draw(elements, on: pageRect, imageDirectory: imageDirectory, context: context.cgContext)
            ink?.draw(in: pageRect)
        }
    }
}
