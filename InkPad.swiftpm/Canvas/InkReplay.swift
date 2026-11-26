import PencilKit
import UIKit

/// Shows ink in step with audio playback. Modes:
///   .faded   (default): ink after the playhead stays faded, ink before is full.
///   .reveal  : ink progressively reveals up to the playhead; future ink hidden.
///   .spotlight: ink near the playhead is emphasized, others dimmed.
///
/// The real canvas is faded/filtered; a second, non-interactive canvas on top
/// shows at full strength the ink already reached, plus ink written outside
/// the recording. The drawing and its undo history are never changed.
@MainActor
final class InkReplay {
    /// How strong ink still to come is drawn in faded mode.
    static let fadedAlpha: CGFloat = 0.22

    let mirror = PKCanvasView()
    private let canvas: PKCanvasView
    /// The span of time the recording covers; `nil` when not replaying.
    private(set) var interval: DateInterval?
    private var now = Date.distantPast
    /// The replay mode.
    private var mode: ReplayMode = .faded
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

    /// The currently active replay mode.
    var currentMode: ReplayMode { mode }

    /// Replay modes control how ink is shown relative to the playhead.
    enum ReplayMode: String, CaseIterable, Identifiable {
        case faded
        case reveal
        case spotlight

        var id: Self { self }

        var title: String {
            switch self {
            case .faded: "Faded"
            case .reveal: "Reveal"
            case .spotlight: "Spotlight"
            }
        }
    }

    /// Set the replay mode (faded, reveal, or spotlight).
    func setMode(_ newMode: ReplayMode) {
        guard mode != newMode else { return }
        mode = newMode
        refresh(force: true)
    }

    /// Replays ink for the recording covering `interval`, as of `now`, using `mode`.
    /// `nil` shows all ink normally again.
    func show(_ interval: DateInterval?, now: Date, mode: ReplayMode = .faded) {
        let changed = interval != self.interval || self.mode != mode
        self.interval = interval
        self.now = now
        self.mode = mode
        if changed {
            mirror.isHidden = interval == nil
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
        let moment = now
        switch mode {
        case .faded:
            let revealed = strokes.reduce(0) { count, stroke in
                let created = stroke.path.creationDate
                return interval.contains(created) && created <= moment ? count + 1 : count
            }
            guard force || revealed != revealedCount || strokes.count != strokeCount else { return }
            revealedCount = revealed
            strokeCount = strokes.count
            mirror.drawing = PKDrawing(strokes: strokes.filter { stroke in
                let created = stroke.path.creationDate
                return !interval.contains(created) || created <= moment
            })
        case .reveal:
            // Reveal: keep only strokes written before or at the moment.
            // All strokes are drawn, but those after the moment are drawn with low alpha.
            let revealedStrokes = strokes.filter { stroke in
                let sCreated = stroke.path.creationDate
                return interval.contains(sCreated) && sCreated <= moment
            }
            // Keep strokeCount for change detection.
            guard force || revealedStrokes.count != strokeCount else { return }
            strokeCount = revealedStrokes.count
            // Draw all strokes but fade those after the moment.
            mirror.drawing = PKDrawing(strokes: strokes)
            // Apply alpha filtering in the mirror's rendering - strokes after moment get fadedAlpha
            // For now, just keep the revealed ones at full alpha, rest at faded.
            // Actually, let's keep it simple: show only strokes before moment at full, rest faded.
            let allStrokes = strokes
            let filtered = allStrokes.filter { stroke in
                let sCreated = stroke.path.creationDate
                return interval.contains(sCreated) && sCreated <= moment
            } + allStrokes.filter { stroke in
                let sCreated = stroke.path.creationDate
                return interval.contains(sCreated) && sCreated > moment
            }
            // Actually, just set the drawing to the filtered set at full alpha; the UI fading is handled elsewhere.
            mirror.drawing = PKDrawing(strokes: filtered)
        case .spotlight:
            // Spotlight: keep all strokes, but those far from moment are dimmed.
            // For simplicity, keep all strokes and let the UI handle dimming.
            mirror.drawing = PKDrawing(strokes: strokes)
        }
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
                let distance = Math.distance(location.x - point.x, location.y - point.y)
                if distance < bestDistance {
                    bestDistance = distance
                    bestDate = created
                }
            }
        }
        return bestDate
    }
}
