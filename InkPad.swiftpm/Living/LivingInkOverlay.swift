import UIKit

/// Small bubbles next to handwriting that other notes also talk about.
/// Sits over the page in page coordinates; only the bubbles take touches.
final class LivingInkOverlay: UIView {
    /// Called with a concept key when its bubble is tapped.
    var onTap: ((String) -> Void)?
    private var bubbles: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        bubbles.first { !$0.isHidden && $0.frame.contains(point) }
    }

    /// Shows bubbles for these concepts starting at `point`; they fade after a while.
    func show(_ concepts: [(key: String, title: String, count: Int)], at point: CGPoint) {
        var origin = point
        for concept in concepts {
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
            configuration.cornerStyle = .capsule
            configuration.image = UIImage(systemName: "leaf.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            configuration.imagePadding = 4
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            var title = AttributedString("\(concept.title) · \(concept.count)")
            title.font = .systemFont(ofSize: 12, weight: .semibold)
            configuration.attributedTitle = title
            let key = concept.key
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.onTap?(key) })
            button.sizeToFit()
            button.frame.origin = origin
            button.alpha = 0
            button.layer.shadowColor = UIColor.systemGreen.cgColor
            button.layer.shadowOpacity = 0.4
            button.layer.shadowRadius = 6
            addSubview(button)
            bubbles.append(button)
            origin.y += button.bounds.height + 4
            UIView.animate(withDuration: 0.3) { button.alpha = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak button] in
                guard let button else { return }
                UIView.animate(withDuration: 0.5, animations: { button.alpha = 0 }) { _ in
                    button.removeFromSuperview()
                    self?.bubbles.removeAll { $0 === button }
                }
            }
        }
    }

    func clear() {
        bubbles.forEach { $0.removeFromSuperview() }
        bubbles = []
    }
}
