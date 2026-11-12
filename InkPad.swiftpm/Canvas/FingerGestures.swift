import UIKit

/// The usual finger shortcuts on a page, like Notability and GoodNotes:
/// by default a two-finger tap undoes, a three-finger tap redoes; each can
/// be given another action (Gestures settings). A small label shows what
/// happened. Pinching and scrolling still belong to the canvas.
@MainActor
final class FingerGestures: NSObject, UIGestureRecognizerDelegate {
    /// Performs the gesture's action; returns the label to show, if any.
    var onTrigger: (GestureTrigger) -> String? = { _ in nil }

    private let twoFingerTap = UITapGestureRecognizer()
    private let threeFingerTap = UITapGestureRecognizer()
    private weak var hudHost: UIView?
    private var hud: UILabel?

    func install(on view: UIView, hudHost: UIView) {
        self.hudHost = hudHost
        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.allowedTouchTypes = direct
        twoFingerTap.addTarget(self, action: #selector(handleTwoFingers))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.allowedTouchTypes = direct
        threeFingerTap.addTarget(self, action: #selector(handleThreeFingers))
        // Three fingers down are not also two.
        twoFingerTap.require(toFail: threeFingerTap)
        for tap in [twoFingerTap, threeFingerTap] {
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }
    }

    @objc private func handleTwoFingers() {
        if let text = onTrigger(.twoFingerTap) { showHUD(text) }
    }

    @objc private func handleThreeFingers() {
        if let text = onTrigger(.threeFingerTap) { showHUD(text) }
    }

    // Plain, not nonisolated: with the nonisolated witness Swift Playgrounds
    // on iPadOS 27 failed to build InkPad (a red X with no message).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }

    /// A short label near the top of the page (already translated).
    func showHUD(_ text: String) {
        guard let host = hudHost else { return }
        hud?.removeFromSuperview()
        let label = PaddedLabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        label.layer.cornerRadius = 16
        label.layer.masksToBounds = true
        label.sizeToFit()
        label.center = CGPoint(x: host.bounds.midX, y: host.bounds.minY + 70)
        label.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        label.alpha = 0
        label.isUserInteractionEnabled = false
        host.addSubview(label)
        hud = label
        let appear: () -> Void = { label.alpha = 1 }
        let fade: () -> Void = { label.alpha = 0 }
        let remove: (Bool) -> Void = { _ in label.removeFromSuperview() }
        UIView.animate(withDuration: 0.12, animations: appear)
        UIView.animate(withDuration: 0.3, delay: 0.7, options: [.beginFromCurrentState], animations: fade, completion: remove)
    }
}

private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let base = super.sizeThatFits(size)
        return CGSize(width: base.width + insets.left + insets.right, height: base.height + insets.top + insets.bottom)
    }
}
