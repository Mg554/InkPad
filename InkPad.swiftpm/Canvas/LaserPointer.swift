import UIKit

/// A laser pointer for explaining a page, like Notability's: a glowing line
/// follows Apple Pencil (or a finger, with finger drawing on) and fades away
/// moments later. Nothing is added to the note. AirPlay mirroring shows it
/// on a projector or TV.
@MainActor
final class LaserPointer: NSObject, UIGestureRecognizerDelegate {
    private let overlay: LaserOverlayView
    /// Starts on touch down, so the dot appears at once.
    private(set) lazy var press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))

    var color: UIColor = .systemRed {
        didSet { overlay.color = color }
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

/// Draws the laser trail in screen coordinates, above the page.
final class LaserOverlayView: UIView {
    private struct Sample {
        let point: CGPoint
        let time: CFTimeInterval
    }

    /// How long the trail stays before it fades out, in seconds.
    static let lifetime: CFTimeInterval = 0.7

    var color: UIColor = .systemRed {
        didSet { applyColors() }
    }

    private var trails: [[Sample]] = []
    private var isPointing = false
    private var displayLink: CADisplayLink?
    private let glowLayer = CAShapeLayer()
    private let coreLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for shape in [glowLayer, coreLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        glowLayer.lineWidth = 12
        coreLayer.lineWidth = 4
        layer.addSublayer(dotLayer)
        for shape in [glowLayer, dotLayer] {
            shape.shadowOffset = .zero
            shape.shadowRadius = 10
            shape.shadowOpacity = 1
        }
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func applyColors() {
        glowLayer.strokeColor = color.withAlphaComponent(0.45).cgColor
        glowLayer.shadowColor = color.cgColor
        coreLayer.strokeColor = color.cgColor
        dotLayer.fillColor = color.cgColor
        dotLayer.shadowColor = color.cgColor
    }

    func begin(at point: CGPoint) {
        trails.append([Sample(point: point, time: CACurrentMediaTime())])
        isPointing = true
        startTicking()
        redraw()
    }

    func move(to point: CGPoint) {
        guard isPointing, !trails.isEmpty else { return }
        trails[trails.count - 1].append(Sample(point: point, time: CACurrentMediaTime()))
        redraw()
    }

    func end() {
        isPointing = false
    }

    func clear() {
        trails = []
        isPointing = false
        stopTicking()
        redraw()
    }

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

    @objc private func tick() {
        let cutoff = CACurrentMediaTime() - Self.lifetime
        for index in trails.indices {
            let isCurrent = isPointing && index == trails.count - 1
            var samples = trails[index].filter { $0.time >= cutoff }
            // Keep the tip while the pencil rests in one place.
            if isCurrent, samples.isEmpty, let last = trails[index].last {
                samples = [last]
            }
            trails[index] = samples
        }
        trails.removeAll { $0.isEmpty }
        if trails.isEmpty && !isPointing {
            stopTicking()
        }
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        for trail in trails {
            guard let first = trail.first else { continue }
            path.move(to: first.point)
            for sample in trail.dropFirst() {
                path.addLine(to: sample.point)
            }
        }
        glowLayer.path = path.cgPath
        coreLayer.path = path.cgPath
        if isPointing, let tip = trails.last?.last?.point {
            dotLayer.path = UIBezierPath(ovalIn: CGRect(x: tip.x - 7, y: tip.y - 7, width: 14, height: 14)).cgPath
        } else {
            dotLayer.path = nil
        }
        CATransaction.commit()
    }
}
