import PencilKit
import UIKit

/// Shows ink in step with audio playback, like Notability: ink written
/// during the recording after the playing moment stays faded until playback
/// reaches it.
///
/// The real canvas is faded, and a second, non-interactive canvas on top
/// shows at full strength the ink already reached, plus ink written outside
/// the recording. The drawing and its undo history are never changed.
@MainActor
final class InkReplay {
    /// How strong ink still to come is drawn.
    static let fadedAlpha: CGFloat = 0.22

    let mirror = PKCanvasView()
    private let canvas: PKCanvasView
    /// The span of time the recording covers; `nil` when not replaying.
    private(set) var interval: DateInterval?
    private var now = Date.distantPast
    // What the mirror shows, to skip redrawing when nothing changed.
    private var revealedCount = -1
    private var strokeCount = -1

    init(canvas: PKCanvasView) {
        self.canvas = canvas
        mirror.isUserInteractionEnabled = false
        mirror.backgroundColor = .clear
        mirror.isOpaque = false
        mirror.drawingPolicy = .pencilOnly
        mirror.showsVerticalScrollIndicator = false
        mirror.showsHorizontalScrollIndicator = false
        mirror.contentInsetAdjustmentBehavior = .never
        mirror.isHidden = true
    }

    var isActive: Bool { interval != nil }

    /// Replays ink for the recording covering `interval`, as of `now`.
    /// `nil` shows all ink normally again.
    func show(_ interval: DateInterval?, now: Date) {
        let changed = interval != self.interval
        self.interval = interval
        self.now = now
        if changed {
            mirror.isHidden = interval == nil
            canvas.alpha = interval == nil ? 1 : Self.fadedAlpha
            revealedCount = -1
            if interval == nil {
                mirror.drawing = PKDrawing()
            }
            syncGeometry()
        }
        refresh(force: changed)
    }

    /// Call after the drawing changes.
    func drawingDidChange() {
        refresh(force: true)
    }

    /// Keeps the mirror scrolled and zoomed exactly like the canvas.
    func syncGeometry() {
        guard isActive else { return }
        mirror.frame = canvas.frame
        mirror.minimumZoomScale = canvas.minimumZoomScale
        mirror.maximumZoomScale = canvas.maximumZoomScale
        if mirror.zoomScale != canvas.zoomScale {
            mirror.zoomScale = canvas.zoomScale
        }
        mirror.contentInset = canvas.adjustedContentInset
        if mirror.contentSize != canvas.contentSize {
            mirror.contentSize = canvas.contentSize
        }
        mirror.contentOffset = canvas.contentOffset
    }

    private func refresh(force: Bool) {
        guard let interval else { return }
        let strokes = canvas.drawing.strokes
        let now = now
        let revealed = strokes.reduce(0) { count, stroke in
            let created = stroke.path.creationDate
            return interval.contains(created) && created <= now ? count + 1 : count
        }
        guard force || revealed != revealedCount || strokes.count != strokeCount else { return }
        revealedCount = revealed
        strokeCount = strokes.count
        mirror.drawing = PKDrawing(strokes: strokes.filter { stroke in
            let created = stroke.path.creationDate
            return !interval.contains(created) || created <= now
        })
    }

    /// When the recording's ink nearest `point` (canvas coordinates) was written.
    func inkDate(near point: CGPoint) -> Date? {
        guard let interval else { return nil }
        let tolerance: CGFloat = 24
        var bestDistance = tolerance
        var bestDate: Date?
        for stroke in canvas.drawing.strokes {
            let created = stroke.path.creationDate
            guard interval.contains(created),
                  stroke.renderBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            else { continue }
            for sample in stroke.path.interpolatedPoints(by: .distance(6)) {
                let location = sample.location.applying(stroke.transform)
                let distance = hypot(location.x - point.x, location.y - point.y)
                if distance < bestDistance {
                    bestDistance = distance
                    bestDate = created
                }
            }
        }
        return bestDate
    }
}
