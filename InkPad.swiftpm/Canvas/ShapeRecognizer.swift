import PencilKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Turns a hand-drawn stroke into a clean line or shape, like Notability's
/// and Apple Notes' "hold to snap".
enum ShapeRecognizer {
    enum Shape: Equatable {
        /// Straight segments through these points (two points: a line).
        case polyline([CGPoint], closed: Bool)
        case ellipse(CGRect)
    }

    /// Returns `nil` when the stroke does not look like a line or shape.
    static func recognize(_ points: [CGPoint]) -> Shape? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        let bounds = boundingBox(points)
        let diagonal = hypot(bounds.width, bounds.height)
        guard diagonal > 16 else { return nil }

        // Straight line: no point strays far from the start-to-end chord.
        let chord = distance(first, last)
        if chord > diagonal * 0.8,
           points.allSatisfy({ distanceToSegment($0, first, last) < max(6, chord * 0.07) }) {
            return .polyline([first, last], closed: false)
        }

        let closed = chord < diagonal * 0.22
        if closed {
            if let ellipse = ellipse(fitting: points, in: bounds) {
                return .ellipse(ellipse)
            }
            let corners = Array(simplify(points + [first], tolerance: diagonal * 0.07).dropLast())
            if (3...6).contains(corners.count) {
                return .polyline(squaredIfRectangle(corners, bounds: bounds), closed: true)
            }
            return nil
        }

        // Open path made of a few straight segments (e.g. an angle or zigzag).
        let corners = simplify(points, tolerance: diagonal * 0.06)
        if (3...5).contains(corners.count) {
            return .polyline(corners, closed: false)
        }
        return nil
    }

    /// The stroke's points in canvas coordinates.
    static func points(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(4)).map { $0.location.applying(stroke.transform) }
    }

    /// A clean, even-width stroke for `shape`.
    static func stroke(for shape: Shape, ink: PKInk, width: CGFloat) -> PKStroke {
        var locations: [CGPoint] = []
        switch shape {
        case let .polyline(corners, closed):
            let path = closed ? corners + [corners[0]] : corners
            for (index, corner) in path.enumerated() {
                // Repeating a control point keeps the spline's corner sharp.
                locations += [corner, corner, corner]
                if index < path.count - 1 {
                    locations += densify(from: corner, to: path[index + 1])
                }
            }
        case let .ellipse(rect):
            let steps = 72
            for step in 0...steps {
                let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
                locations.append(CGPoint(x: rect.midX + rect.width / 2 * cos(angle), y: rect.midY + rect.height / 2 * sin(angle)))
            }
        }
        let size = CGSize(width: width, height: width)
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.005,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// The same stroke with an even width and opacity, as if drawn with
    /// constant pressure. The nib shape of each point is kept.
    static func withoutPressure(_ stroke: PKStroke, width: CGFloat) -> PKStroke {
        let path = stroke.path
        guard !path.isEmpty else { return stroke }
        let sizes = path.map(\.size).sorted { $0.width < $1.width }
        let median = sizes[sizes.count / 2]
        let aspect = median.width > 0 ? median.height / median.width : 1
        let size = CGSize(width: width, height: width * aspect)
        let opacity = path.map(\.opacity).max() ?? 1
        let points = path.map { point in
            PKStrokePoint(
                location: point.location,
                timeOffset: point.timeOffset,
                size: size,
                opacity: opacity,
                force: 1,
                azimuth: point.azimuth,
                altitude: point.altitude
            )
        }
        var even = stroke
        even.path = PKStrokePath(controlPoints: points, creationDate: path.creationDate)
        return even
    }

    // MARK: Geometry

    private static func ellipse(fitting points: [CGPoint], in bounds: CGRect) -> CGRect? {
        let radiusX = bounds.width / 2
        let radiusY = bounds.height / 2
        guard radiusX > 4, radiusY > 4 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let errors = points.map { point -> CGFloat in
            let dx = (point.x - center.x) / radiusX
            let dy = (point.y - center.y) / radiusY
            return abs(sqrt(dx * dx + dy * dy) - 1)
        }
        let meanError = errors.reduce(0, +) / CGFloat(errors.count)
        guard meanError < 0.09 else { return nil }
        // Nearly round: make it a circle.
        if abs(radiusX - radiusY) < max(radiusX, radiusY) * 0.15 {
            let radius = (radiusX + radiusY) / 2
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
        return bounds
    }

    /// Four corners close to the bounding box become an exact rectangle.
    private static func squaredIfRectangle(_ corners: [CGPoint], bounds: CGRect) -> [CGPoint] {
        guard corners.count == 4 else { return corners }
        let boxCorners = [
            CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
        ]
        let tolerance = hypot(bounds.width, bounds.height) * 0.12
        let nearBox = corners.allSatisfy { corner in boxCorners.contains { distance($0, corner) < tolerance } }
        guard nearBox else { return corners }
        // Keep the drawing direction: start from the box corner nearest the first point.
        let start = boxCorners.indices.min { distance(boxCorners[$0], corners[0]) < distance(boxCorners[$1], corners[0]) } ?? 0
        let clockwise = cross(corners[0], corners[1], corners[2]) > 0
        return (0..<4).map { boxCorners[(start + (clockwise ? $0 : 4 - $0)) % 4] }
    }

    /// Ramer–Douglas–Peucker simplification.
    private static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0
        var maxDistance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let d = distanceToSegment(points[index], first, last)
            if d > maxDistance {
                maxDistance = d
                farthest = index
            }
        }
        guard maxDistance > tolerance else { return [first, last] }
        let left = simplify(Array(points[...farthest]), tolerance: tolerance)
        let right = simplify(Array(points[farthest...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    private static func densify(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let steps = max(Int(distance(start, end) / 8), 1)
        return (1..<steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
    }

    private static func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}

/// Watches touches on the canvas without taking them over. Records the
/// stroke's points, and reports when the touch has rested in place long
/// enough to snap (while still down, like Notability), and when it ends.
final class StrokeHoldTracker: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// How long the touch must rest to snap.
    static let holdDuration: TimeInterval = 0.5
    static let stillDistance: CGFloat = 3

    /// Points are recorded in this view's coordinates (the canvas content).
    weak var coordinateView: UIView?
    var onTouchBegan: (() -> Void)?
    /// Called once per touch, with the points drawn so far.
    var onHold: (([CGPoint]) -> Void)?
    var onTouchEnded: (() -> Void)?

    private var points: [CGPoint] = []
    private var lastMoveLocation: CGPoint = .zero
    private var holdTimer: Timer?
    private var didHold = false

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        didHold = false
        let location = touch.location(in: coordinateView)
        points = [location]
        lastMoveLocation = location
        onTouchBegan?()
        restartHoldTimer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, !didHold else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            points.append(sample.location(in: coordinateView))
        }
        let location = touch.location(in: coordinateView)
        if hypot(location.x - lastMoveLocation.x, location.y - lastMoveLocation.y) > Self.stillDistance {
            lastMoveLocation = location
            restartHoldTimer()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
        onTouchEnded?()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish()
        state = .failed
    }

    override func reset() {
        super.reset()
        finish()
    }

    private func restartHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            guard let self, !self.didHold, self.points.count > 2 else { return }
            self.didHold = true
            self.onHold?(self.points)
        }
    }

    private func finish() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
