import PencilKit
import UIKit

/// Renders a small preview of a note's first page for the library grid.
@MainActor
enum ThumbnailRenderer {
    static let scale: CGFloat = 0.3

    static func pngData(for content: NoteContent) -> Data? {
        let background = content.makeBackground()
        guard let pageRect = background.layout.pageRects.first else { return nil }

        // Render ink with light-mode colors so it matches the white paper.
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = content.drawing.image(from: pageRect, scale: 1)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
            background.drawPage(at: 0, in: context.cgContext)
            ink.draw(in: pageRect)
        }
        return image.pngData()
    }
}
