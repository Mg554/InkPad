import UIKit

/// The usual finger shortcuts on a page, like Notability and GoodNotes:
/// a two-finger tap undoes, a three-finger tap redoes. A small label shows
/// what happened. Pinching and scrolling still belong to the canvas.
@MainActor
final class FingerGestures: NSObject, UIGestureRecognizerDelegate {
    var onUndo: () -> Bool = { false }
    var onRedo: () -> Bool = { false }

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
        let done = onUndo()
        showHUD(done ? "Undo" : "Nothing to Undo", symbol: "arrow.uturn.backward")
    }

    @objc private func handleThreeFingers() {
        let done = onRedo()
        showHUD(done ? "Redo" : "Nothing to Redo", symbol: "arrow.uturn.forward")
    }

    // Plain, not nonisolated: with the nonisolated witness Swift Playgrounds
    // on iPadOS 27 failed to build InkPad (a red X with no message).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }

    private func showHUD(_ text: String, symbol: String) {
        guard let host = hudHost else { return }
        hud?.removeFromSuperview()
        let label = PaddedLabel()
        let symbolName: String = symbol
        label.text = "\u{21BA}  " + tr(text)
        if symbolName.hasSuffix("forward") { label.text = "\u{21BB}  " + tr(text) }
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
