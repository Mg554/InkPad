import UIKit

/// A comment pin on the page: a small speech-bubble badge, with the thread
/// behind it. With the Text tool it can be dragged; a tap with any tool
/// opens its thread (see `NoteCanvasHostView`).
final class CommentPinView: PageElementView {
    private(set) var comment: NoteComment
    private let badge = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right.fill"))

    static let size = CGSize(width: 40, height: 36)

    init(id: UUID, frame: CGRect, comment: NoteComment, isLocked: Bool = false) {
        self.comment = comment
        super.init(id: id, frame: CGRect(origin: frame.origin, size: Self.size), isLocked: isLocked)
        backgroundColor = .clear
        isOpaque = false
        badge.contentMode = .center
        badge.frame.size = Self.size
        badge.isUserInteractionEnabled = false
        addSubview(badge)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(_ newComment: NoteComment) {
        comment = newComment
        refresh()
    }

    private func refresh() {
        badge.tintColor = comment.isResolved ?? false ? .systemGray : .systemYellow
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        badge.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func makeElement() -> PageElement? {
        PageElement(id: id, frame: frame, content: .comment(comment), isLocked: isElementLocked ? true : nil)
    }

    @objc func handleTap() {
        layerView?.endEditing(true)
        layerView?.selectElement(self)
        layerView?.onCommentTap?(self)
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        guard !isElementLocked else { return }
        if gesture.state == .began {
            layerView?.endEditing(true)
            layerView?.selectElement(self)
        }
        let translation = takeTranslation(gesture)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }
}
