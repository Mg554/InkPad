import UIKit

/// A sticky note on the page. With the Text tool it can be dragged and
/// resized; a tap with any tool opens it (see `NoteCanvasHostView`).
final class StickyNoteView: PageElementView {
    private(set) var note: StickyNote
    /// The unfolded size, kept while folded.
    private var fullSize: CGSize
    private var resizeHandle: UIView!

    init(id: UUID, frame: CGRect, note: StickyNote) {
        self.note = note
        fullSize = frame.size
        super.init(id: id, frame: StickyNote.visibleFrame(frame, folded: note.isFolded))
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        resizeHandle = makeHandle(systemImage: "arrow.up.left.and.arrow.down.right", action: #selector(handleResize(_:)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The whole note's frame, as if unfolded.
    var fullFrame: CGRect { CGRect(origin: frame.origin, size: fullSize) }

    func update(_ newNote: StickyNote) {
        note = newNote
        frame = StickyNote.visibleFrame(fullFrame, folded: newNote.isFolded)
        updateSelectionAppearance()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        note.draw(in: bounds.insetBy(dx: 1, dy: 1), context: context)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizeHandle.center = CGPoint(x: bounds.width, y: bounds.height)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isSelected, !resizeHandle.isHidden, resizeHandle.frame.contains(point) {
            return true
        }
        return super.point(inside: point, with: event)
    }

    override func updateSelectionAppearance() {
        super.updateSelectionAppearance()
        layer.cornerRadius = 4
        resizeHandle.isHidden = !isSelected || note.isFolded
    }

    override func makeElement() -> PageElement? {
        PageElement(id: id, frame: fullFrame, content: .sticky(note))
    }

    @objc private func handleTap() {
        layerView?.endEditing(true)
        layerView?.selectElement(self)
        layerView?.onStickyTap?(self)
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            layerView?.endEditing(true)
            layerView?.selectElement(self)
        }
        let translation = takeTranslation(gesture)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        guard !note.isFolded else { return }
        let translation = takeTranslation(gesture)
        let width = min(max(100, frame.width + translation.x), 600)
        let height = min(max(100, frame.height + translation.y), 600)
        frame.size = CGSize(width: width, height: height)
        fullSize = frame.size
        setNeedsDisplay()
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }
}
