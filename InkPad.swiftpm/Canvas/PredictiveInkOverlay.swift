import UIKit

/// A faint line drawn just ahead of the pencil while a stroke is in progress.
/// It uses the last samples' velocity and acceleration to estimate 1–2 frames
/// ahead, then clears when the real PencilKit stroke arrives. Committed ink is
/// never modified.
final class PredictiveInkOverlay: UIView {
    private let shape = CAShapeLayer()
    private var samples: [CGPoint] = []

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "predictiveInk") == nil { return true }
            return UserDefaults.standard.bool(forKey: "predictiveInk")
        }
        set { UserDefaults.standard.set(newValue, forKey: "predictiveInk") }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = UIColor.label.withAlphaComponent(0.45).cgColor
        shape.lineWidth = 2
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.opacity = 0
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
    }

    func update(_ points: [CGPoint]) {
        guard isEnabled, points.count >= 2 else { clear(); return }
        samples = Array(points.suffix(12))
        let path = UIBezierPath()
        let start = samples[samples.count - 2]
        let tip = samples[samples.count - 1]
        path.move(to: start)
        path.addLine(to: tip)
        path.addLine(to: predict(from: samples))
        shape.path = path.cgPath
        shape.opacity = 1
    }

    func clear() {
        samples = []
        shape.path = nil
        shape.opacity = 0
    }

    private func predict(from points: [CGPoint]) -> CGPoint {
        let last = points[points.count - 1]
        let previous = points[points.count - 2]
        let velocity = CGPoint(x: last.x - previous.x, y: last.y - previous.y)
        var acceleration = CGPoint.zero
        if points.count >= 3 {
            let before = points[points.count - 3]
            let prior = CGPoint(x: previous.x - before.x, y: previous.y - before.y)
            acceleration = CGPoint(x: velocity.x - prior.x, y: velocity.y - prior.y)
        }
        return CGPoint(
            x: last.x + velocity.x * 1.5 + acceleration.x * 0.5,
            y: last.y + velocity.y * 1.5 + acceleration.y * 0.5
        )
    }
}
