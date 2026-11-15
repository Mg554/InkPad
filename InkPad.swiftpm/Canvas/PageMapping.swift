import CoreGraphics
import PencilKit

/// Moves content from one page layout to another: pages stacked down the
/// screen become pages across it. The page each piece of content is on is
/// found by where it sits, and it takes that page's move.
///
/// Only geometry lives here, so it can be tested on its own.
enum PageMapping {
    /// The move that takes a point in the source layout to the target one.
    /// `nil` when the layouts agree, or when the point is not on any page.
    static func move(for point: CGPoint, from source: PageLayout, to target: PageLayout) -> CGAffineTransform? {
        guard source.axis != target.axis, source.pageRects.count == target.pageRects.count else { return nil }
        let axis = source.axis
        if let index = source.pageRects.firstIndex(where: { $0.contains(point) }) {
            return move(forPageAt: index, from: source, to: target)
        }
        // In the gap between pages: the content belongs to the page before
        // it, and takes that page's move.
        let position = axis == .vertical ? point.y : point.x
        guard let index = source.pageRects.lastIndex(where: { axis.minCorner(of: $0) <= position }) else { return nil }
        return move(forPageAt: index, from: source, to: target)
    }

    /// The move of one page: where it starts in the target layout minus
    /// where it starts in the source one.
    static func move(forPageAt index: Int, from source: PageLayout, to target: PageLayout) -> CGAffineTransform? {
        guard source.pageRects.indices.contains(index), target.pageRects.indices.contains(index) else { return nil }
        let from = source.pageRects[index]
        let to = target.pageRects[index]
        let move = CGAffineTransform(translationX: to.minX - from.minX, y: to.minY - from.minY)
        return move.isIdentity ? nil : move
    }

    /// The ink of one drawing, moved from the source layout to the target.
    static func drawing(_ drawing: PKDrawing, from source: PageLayout, to target: PageLayout) -> PKDrawing {
        guard source.axis != target.axis, source.pageRects.count == target.pageRects.count else { return drawing }
        return PKDrawing(strokes: drawing.strokes.map { stroke in
            let bounds = stroke.renderBounds
            guard let move = move(for: CGPoint(x: bounds.midX, y: bounds.midY), from: source, to: target) else { return stroke }
            var moved = stroke
            moved.transform = stroke.transform.concatenating(move)
            return moved
        })
    }

    /// The coordinate of a point in the target layout.
    static func point(_ point: CGPoint, from source: PageLayout, to target: PageLayout) -> CGPoint {
        guard let move = move(for: point, from: source, to: target) else { return point }
        return point.applying(move)
    }
}
