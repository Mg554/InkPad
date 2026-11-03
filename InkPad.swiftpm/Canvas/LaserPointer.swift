import UIKit

/// A laser pointer for explaining a page, like Notability's: a smooth,
/// glowing line follows Apple Pencil (or a finger, with finger drawing on).
/// It stays while you point and fades softly a moment after you lift the
/// pencil; with Tail on, only a short trail follows the pencil. Nothing is
/// added to the note. AirPlay mirroring shows it on a projector or TV.
@MainActor
final class LaserPointer: NSObject, UIGestureRecognizerDelegate {
    private let overlay: LaserOverlayView
    /// Starts on touch down, so the dot appears at once.
    private(set) lazy var press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))

    var color: UIColor = .systemRed {
        didSet { overlay.color = color }
    }

    var leavesTail = false {
        didSet { overlay.leavesTail = leavesTail }
    }

    init(gestureView: UIView, overlay: LaserOverlayView) {
        self.overlay = overlay
        super.init()
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.delegate = self
        press.isEnabled = false
        gestureView.addGestureRecognizer(press)
    }

    func setEnabled(_ enabled: Bool, pencilOnly: Bool) {
        press.isEnabled = enabled
        let pencil = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        let all = [UITouch.TouchType.direct, .pencil, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        press.allowedTouchTypes = pencilOnly ? pencil : all
        if !enabled { overlay.clear() }
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: overlay)
        switch gesture.state {
        case .began: overlay.begin(at: point)
        case .changed: overlay.move(to: point)
        default: overlay.end()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }
}

/// Draws the laser in screen coordinates, above the page.
final class LaserOverlayView: UIView {
    /// One line, from touch down to lift.
    private final class Stroke {
        var points: [CGPoint] = []
        var times: [CFTimeInterval] = []
        let container = CALayer()
        let glow = CAShapeLayer()
        let core = CAShapeLayer()
    }

    /// How long the line stays after the pencil lifts before it fades.
    static let holdTime: TimeInterval = 0.55
    /// How long the fade takes.
    static let fadeTime: CFTimeInterval = 0.65
    /// With Tail on: how much of the line follows the pencil, in seconds.
    static let tailLength: CFTimeInterval = 0.45

    var color: UIColor = .systemRed {
        didSet { applyColors() }
    }

    var leavesTail = false

    private var strokes: [Stroke] = []
    private var current: Stroke?
    /// Bumped on every touch, so a fade waits for the last lift.
    private var generation = 0
    private var displayLink: CADisplayLink?
    private let dot = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        dot.shadowOffset = .zero
        dot.shadowRadius = 8
        dot.shadowOpacity = 1
        layer.addSublayer(dot)
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func applyColors() {
        dot.fillColor = color.cgColor
        dot.shadowColor = color.cgColor
        for stroke in strokes {
            style(stroke)
        }
    }

    private func style(_ stroke: Stroke) {
        stroke.glow.strokeColor = color.withAlphaComponent(0.35).cgColor
        stroke.glow.shadowColor = color.cgColor
        stroke.core.strokeColor = color.cgColor
    }

    // MARK: Touches

    func begin(at point: CGPoint) {
        generation += 1
        let stroke = Stroke()
        for shape in [stroke.glow, stroke.core] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            stroke.container.addSublayer(shape)
        }
        stroke.glow.lineWidth = 11
        stroke.glow.shadowOffset = .zero
        stroke.glow.shadowRadius = 7
        stroke.glow.shadowOpacity = 0.9
        stroke.core.lineWidth = 4.5
        style(stroke)
        layer.insertSublayer(stroke.container, below: dot)
        strokes.append(stroke)
        current = stroke
        add(point, to: stroke)
        dot.opacity = 1
        moveDot(to: point)
        if leavesTail { startTicking() }
    }

    func move(to point: CGPoint) {
        guard let current else { return }
        add(point, to: current)
        moveDot(to: point)
    }

    func end() {
        guard current != nil else { return }
        current = nil
        fadeDot()
        guard !leavesTail else { return }
        // Keep everything on screen a moment, then fade it all together,
        // unless the pencil comes down again first.
        let ending = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdTime) { [weak self] in
            guard let self, self.generation == ending, self.current == nil else { return }
            self.fadeAll()
        }
    }

    func clear() {
        generation += 1
        current = nil
        stopTicking()
        strokes.forEach { $0.container.removeFromSuperlayer() }
        strokes = []
        dot.opacity = 0
    }

    private func add(_ point: CGPoint, to stroke: Stroke) {
        // Skip tiny moves: they only add jitter.
        if let last = stroke.points.last, hypot(point.x - last.x, point.y - last.y) < 1.2 { return }
        stroke.points.append(point)
        stroke.times.append(CACurrentMediaTime())
        redraw(stroke)
    }

    // MARK: Drawing

    private func redraw(_ stroke: Stroke) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = Self.smoothPath(through: stroke.points)
        stroke.glow.path = path
        stroke.core.path = path
        CATransaction.commit()
    }

    /// A smooth curve through the points (quadratic curves between midpoints).
    private static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path.cgPath }
        path.move(to: first)
        guard points.count > 2 else {
            if points.count == 2 {
                path.addLine(to: points[1])
            } else {
                // A single touch: a dot.
                path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            }
            return path.cgPath
        }
        for index in 1..<(points.count - 1) {
            let point = points[index]
            let next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), controlPoint: point)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path.cgPath
    }

    private func moveDot(to point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.path = UIBezierPath(ovalIn: CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13)).cgPath
        CATransaction.commit()
    }

    private func fadeDot() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = dot.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.25
        dot.opacity = 0
        dot.add(fade, forKey: "fade")
    }

    /// Fades every line on screen with an ease, then removes them.
    private func fadeAll() {
        let fading = strokes
        strokes = []
        for stroke in fading {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Self.fadeTime
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            stroke.container.opacity = 0
            stroke.container.add(fade, forKey: "fade")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeTime + 0.05) {
            fading.forEach { $0.container.removeFromSuperlayer() }
        }
    }

    // MARK: Tail

    private func startTicking() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// With Tail on, drops the oldest part of each line as time passes.
    @objc private func tick() {
        let cutoff = CACurrentMediaTime() - Self.tailLength
        for stroke in strokes {
            let isCurrent = stroke === current
            let keep = stroke.times.firstIndex { $0 >= cutoff } ?? stroke.times.count
            // The tip stays while the pencil rests in one place.
            let drop = isCurrent ? min(keep, max(stroke.points.count - 1, 0)) : keep
            if drop > 0 {
                stroke.points.removeFirst(drop)
                stroke.times.removeFirst(drop)
                redraw(stroke)
            }
        }
        let finished = strokes.filter { $0.points.isEmpty && $0 !== current }
        finished.forEach { $0.container.removeFromSuperlayer() }
        strokes.removeAll { stroke in finished.contains { $0 === stroke } }
        if strokes.isEmpty && current == nil {
            stopTicking()
        }
    }
}
