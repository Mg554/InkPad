import PencilKit
import UIKit

/// Shared way to turn PencilKit ink into pictures. Ink renders in light
/// mode by default, which draws it dark — what paper, previews and reading
/// all want.
enum InkSnapshot {
    /// The drawing's ink, rendered in the given interface style.
    static func snapshot(of drawing: PKDrawing, from bounds: CGRect, scale: CGFloat, dark: Bool = false) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        return image
    }

    /// The drawing dark on white: what thumbnails show and Vision reads
    /// best. Render the ink first, then fill white behind it.
    static func onWhite(of drawing: PKDrawing, from bounds: CGRect, scale: CGFloat) -> UIImage {
        let ink = snapshot(of: drawing, from: bounds, scale: scale)
        let renderer = UIGraphicsImageRenderer(size: ink.size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }
    }
}
