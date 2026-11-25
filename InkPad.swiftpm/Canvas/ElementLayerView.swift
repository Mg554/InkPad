import UIKit

/// Holds the text boxes and images, in canvas coordinates. It sits between
/// the page background and the ink, so ink is drawn over text and images.
/// Elements only receive touches while the Text tool is active.
final class ElementLayerView: UIView {
    var imageDirectory: URL?
    /// Called after any element is added, edited, moved, resized or removed.
    var onChange: (() -> Void)?
    var onSelectionChange: ((PageElementView?) -> Void)?
    /// Called when the caret or text selection moves, so formatting buttons can update.
    var onTextStateChange: (() -> Void)?
    /// Called when a sticky note is tapped, to open it.
    var onStickyTap: ((StickyNoteView) -> Void)?
    var onCommentTap: ((CommentPinView) -> Void)?

    private(set) weak var selected: PageElementView?
    private var renderScale: CGFloat = 2
    /// Which way the pages run, for the moves that follow page changes.
    var axis: PageLayout.Axis = .vertical

    var isInteractive = false {
        didSet {
            guard isInteractive != oldValue else { return }
            if !isInteractive {
                endEditing(true)
                selectElement(nil)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Returns an element (or one of its handles), never the layer itself.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isInteractive, let hit = super.hitTest(point, with: event), hit !== self else { return nil }
        return hit
    }

    // MARK: Contents

    func load(_ elements: [PageElement]) {
        subviews.forEach { $0.removeFromSuperview() }
        for element in elements {
            let locked = element.isLocked ?? false
            switch element.content {
            case let .text(rtf):
                let text = TextBoxStyle.attributedString(fromRTF: rtf) ?? NSAttributedString()
                let box = TextBoxView(id: element.id, frame: element.frame, text: text, isLocked: locked)
                box.anchorTo = element.anchorTo
                add(box)
            case let .image(file):
                guard isPlainFileName(file),
                      let directory = imageDirectory,
                      let image = UIImage(contentsOfFile: directory.appendingPathComponent(file).path)
                else {
                    // Keep the reference so a missing file is not silently dropped on save.
                    add(ImageElementView(id: element.id, frame: element.frame, file: file, image: nil, isLocked: locked))
                    continue
                }
                add(ImageElementView(id: element.id, frame: element.frame, file: file, image: image, isLocked: locked))
            case let .sticky(note):
                add(StickyNoteView(id: element.id, frame: element.frame, note: note, isLocked: locked))
            case let .comment(comment):
                add(CommentPinView(id: element.id, frame: element.frame, comment: comment, isLocked: locked))
            case let .tape(tape):
                let tapeView = TapeElementView(id: element.id, frame: tape.frame, red: CGFloat(tape.red), green: CGFloat(tape.green), blue: CGFloat(tape.blue), style: tape.style)
                add(tapeView)
            }
        }
    }

    var elements: [PageElement] {
        subviews.compactMap { ($0 as? PageElementView)?.makeElement() }
    }

    @discardableResult
    func addTextBox(at point: CGPoint) -> TextBoxView {
        let width = min(TextBoxStyle.defaultWidth, max(bounds.width - point.x, TextBoxStyle.minimumWidth))
        let frame = CGRect(x: point.x - TextBoxStyle.padding, y: point.y - 22, width: width, height: 44)
        let box = TextBoxView(id: UUID(), frame: frame, text: NSAttributedString())
        add(box)
        box.textView.becomeFirstResponder()
        return box
    }

    /// A finished text box placed just below `rect` (Think › Add to Page).
    func addTextBox(_ text: NSAttributedString, below rect: CGRect) {
        let width = min(PageLayout.pageWidth - 48, max(rect.width, 480))
        let x = min(max(rect.minX, 24), PageLayout.pageWidth - 24 - width)
        let frame = CGRect(x: x, y: rect.maxY + 12, width: width, height: 44)
        let box = TextBoxView(id: UUID(), frame: frame, text: text)
        add(box)
        selectElement(box)
        elementsDidChange()
    }

    /// A text box holding `text` at an exact spot, where handwriting
    /// becomes editable text (Lasso › Make Editable Text).
    @discardableResult
    func addTextBox(_ text: NSAttributedString, at frame: CGRect) -> TextBoxView {
        let box = TextBoxView(id: UUID(), frame: frame, text: text)
        add(box)
        elementsDidChange()
        return box
    }

    @discardableResult
    func addImage(file: String, image: UIImage, pixelSize: CGSize, centeredAt center: CGPoint) -> CGRect {
        let maxWidth = PageLayout.pageWidth * 0.6
        let width = min(maxWidth, pixelSize.width / 2)
        let height = width * pixelSize.height / max(pixelSize.width, 1)
        let frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let view = ImageElementView(id: UUID(), frame: frame, file: file, image: image)
        add(view)
        selectElement(view)
        elementsDidChange()
        return frame
    }

    // MARK: Sticky notes

    /// A new sticky note centered at `center`.
    @discardableResult
    func addSticky(_ note: StickyNote, centeredAt center: CGPoint) -> StickyNoteView {
        let size = StickyNote.defaultSize
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let view = StickyNoteView(id: UUID(), frame: frame, note: note)
        add(view)
        elementsDidChange()
        return view
    }

    /// The top element under `point` (layer coordinates).
    func element(at point: CGPoint) -> PageElementView? {
        for case let view as PageElementView in subviews.reversed() where view.frame.contains(point) {
            return view
        }
        return nil
    }

    /// A picture centered at `center` (a drop).
    @discardableResult
    func addImage(file: String, image: UIImage, size: CGSize, centeredAt center: CGPoint) -> CGRect {
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let view = ImageElementView(id: UUID(), frame: frame, file: file, image: image)
        add(view)
        elementsDidChange()
        return frame
    }

    func sticky(_ id: UUID) -> StickyNoteView? {
        subviews.first(where: { ($0 as? StickyNoteView)?.id == id }) as? StickyNoteView
    }

    /// The top sticky note under `point` (layer coordinates).
    func sticky(at point: CGPoint) -> StickyNoteView? {
        for case let view as StickyNoteView in subviews.reversed() where view.frame.contains(point) {
            return view
        }
        return nil
    }

    func updateSticky(_ id: UUID, with note: StickyNote) {
        guard let view = sticky(id) else { return }
        view.update(note)
        bringSubviewToFront(view)
        elementsDidChange()
    }

    // MARK: Comments

    /// A new comment pin centered at `center`.
    @discardableResult
    func addComment(_ comment: NoteComment, centeredAt center: CGPoint) -> CommentPinView {
        let size = CommentPinView.size
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let view = CommentPinView(id: UUID(), frame: frame, comment: comment)
        add(view)
        elementsDidChange()
        return view
    }

    func commentPin(_ id: UUID) -> CommentPinView? {
        subviews.first(where: { ($0 as? CommentPinView)?.id == id }) as? CommentPinView
    }

    /// The top comment pin under `point` (layer coordinates).
    func comment(at point: CGPoint) -> CommentPinView? {
        for case let view as CommentPinView in subviews.reversed() where view.frame.contains(point) {
            return view
        }
        return nil
    }

    func updateComment(_ id: UUID, with comment: NoteComment) {
        guard let view = commentPin(id) else { return }
        view.update(comment)
        bringSubviewToFront(view)
        elementsDidChange()
    }

    func removeElement(_ id: UUID) {
        guard let view = subviews.first(where: { ($0 as? PageElementView)?.id == id }) as? PageElementView else { return }
        remove(view)
    }

    /// Takes the element with `id` out of the layer and hands it back, so an
    /// undo can put it where it was. Its text and frame are untouched.
    @discardableResult
    func detach(_ id: UUID) -> PageElementView? {
        guard let view = subviews.first(where: { ($0 as? PageElementView)?.id == id }) as? PageElementView else { return nil }
        if view === selected { selectElement(nil) }
        view.removeFromSuperview()
        return view
    }

    /// Puts a detached element back (undo of a handwriting conversion).
    func restore(_ view: PageElementView) {
        add(view)
        elementsDidChange()
    }

    private func add(_ view: PageElementView) {
        view.layerView = self
        if let box = view as? TextBoxView, box.anchorTo == nil {
            box.anchorTo = nearestBlockAbove(box)
        }
        addSubview(view)
        view.setRenderScale(renderScale)
    }

    /// The closest text block directly above `view`, used as its anchor.
    private func nearestBlockAbove(_ view: TextBoxView) -> UUID? {
        var best: TextBoxView?
        var bestGap: CGFloat = 70
        for other in subviews where other !== view {
            guard let box = other as? TextBoxView else { continue }
            let gap = view.frame.minY - box.frame.maxY
            guard gap >= -4, gap < bestGap else { continue }
            best = box
            bestGap = gap
        }
        return best?.id
    }

    /// Keeps anchored blocks below a resized block from overlapping it.
    func anchorDidResize(_ source: TextBoxView, delta: CGFloat) {
        guard abs(delta) > 0.5 else { return }
        for case let view as PageElementView in subviews where view !== source {
            guard view.anchorTo == source.id, view.frame.minY >= source.frame.maxY - 70 else { continue }
            view.center.y += delta
        }
    }

    // MARK: Selection and editing

    func selectElement(_ view: PageElementView?) {
        guard view !== selected else { return }
        selected?.isSelected = false
        selected = view
        view?.isSelected = true
        if let view {
            bringSubviewToFront(view)
        }
        onSelectionChange?(view)
    }

    func removeSelected() {
        guard let selected, !selected.isElementLocked else { return }
        remove(selected)
    }

    func remove(_ view: PageElementView) {
        if view === selected {
            selectElement(nil)
        }
        view.removeFromSuperview()
        elementsDidChange()
    }

    func elementsDidChange() {
        onChange?()
    }

    /// Moves elements past `value` along the pages' direction by `delta`,
    /// and removes those whose middle falls in `removing`. Used when pages
    /// are inserted or deleted.
    func shiftElements(below value: CGFloat, by delta: CGFloat, removing: ClosedRange<CGFloat>?) {
        var changed = false
        for case let view as PageElementView in subviews {
            let middle = axis.mid(of: view.frame)
            if let removing, removing.contains(middle) {
                if view === selected { selectElement(nil) }
                view.removeFromSuperview()
                changed = true
            } else if middle > value {
                if axis == .vertical {
                    view.center.y += delta
                } else {
                    view.center.x += delta
                }
                changed = true
            }
        }
        if changed { elementsDidChange() }
    }

    /// Moves elements along the pages' direction; `offset` says how far
    /// content at a given position moves (used to reorder pages).
    func moveElements(by offset: (CGFloat) -> CGFloat) {
        var changed = false
        for case let view as PageElementView in subviews {
            let delta = offset(axis.mid(of: view.frame))
            guard delta != 0 else { continue }
            if axis == .vertical {
                view.center.y += delta
            } else {
                view.center.x += delta
            }
            changed = true
        }
        if changed { elementsDidChange() }
    }

    /// Re-rasterizes text for the current zoom so it stays sharp.
    func setRenderScale(_ scale: CGFloat) {
        renderScale = scale
        for case let view as PageElementView in subviews {
            view.setRenderScale(scale)
        }
    }

    // MARK: Z-order and lock

    /// The element views in drawing order (back to front).
    private var elementViews: [PageElementView] {
        subviews.compactMap { $0 as? PageElementView }
    }

    func bringSelectedForward() {
        guard let selected else { return }
        let views = elementViews
        guard let index = views.firstIndex(where: { $0 === selected }), index < views.count - 1 else { return }
        exchangeSubview(at: subviews.firstIndex(of: selected)!, withSubviewAt: subviews.firstIndex(of: views[index + 1])!)
        elementsDidChange()
    }

    func sendSelectedBackward() {
        guard let selected else { return }
        let views = elementViews
        guard let index = views.firstIndex(where: { $0 === selected }), index > 0 else { return }
        exchangeSubview(at: subviews.firstIndex(of: selected)!, withSubviewAt: subviews.firstIndex(of: views[index - 1])!)
        elementsDidChange()
    }

    func bringSelectedToFront() {
        guard let selected else { return }
        bringSubviewToFront(selected)
        elementsDidChange()
    }

    func sendSelectedToBack() {
        guard let selected else { return }
        sendSubviewToBack(selected)
        elementsDidChange()
    }

    func toggleLockSelected() {
        guard let selected else { return }
        selected.setLocked(!selected.isElementLocked)
    }

    var isSelectedLocked: Bool { selected?.isElementLocked ?? false }
}

/// A tape mask element view that displays an opaque rounded rect.
/// The user can move and select it; delete via the toolbar.
final class TapeElementView: PageElementView {
    private let red: CGFloat, green: CGFloat, blue: CGFloat
    private let style: TapeStyle

    init(id: UUID, frame: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat, style: TapeStyle) {
        self.red = red
        self.green = green
        self.blue = blue
        self.style = style
        super.init(id: id, frame: frame, isLocked: false)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        layer.masksToBounds = true
        // Set background color from RGB components
        backgroundColor = UIColor(red: red, green: green, blue: blue, alpha: 1)
        // Tap to select the element
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        // Pan to move the element
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
    }

    @objc func handleTap() {
        layerView?.selectElement(self)
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isElementLocked else { return }
        switch gesture.state {
        case .began:
            layerView?.endEditing(true)
            layerView?.selectElement(self)
        case .changed:
            let translation = takeTranslation(gesture)
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        case .possible, .failed, .ended, .cancelled:
            layerView?.elementsDidChange()
        @unknown default:
            layerView?.elementsDidChange()
        }
    }

    override func makeElement() -> PageElement? {
        PageElement(id: id, frame: frame, content: .tape(TapeMask(id: id, frame: frame, red: Double(red), green: Double(green), blue: Double(blue), style: style)), isLocked: isElementLocked ? true : nil)
    }
}

// Base class for a movable element on the page.
class PageElementView: UIView {
    let id: UUID
    var anchorTo: UUID?
    weak var layerView: ElementLayerView?
    private(set) var isElementLocked: Bool

    var isSelected = false {
        didSet { updateSelectionAppearance() }
    }

    init(id: UUID, frame: CGRect, isLocked: Bool = false) {
        self.id = id
        self.isElementLocked = isLocked
        super.init(frame: frame)
        layer.borderColor = UIColor.systemBlue.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func makeElement() -> PageElement? { nil }

    /// Toggles the lock and refreshes handles/appearance.
    func setLocked(_ locked: Bool) {
        isElementLocked = locked
        updateSelectionAppearance()
        layerView?.elementsDidChange()
    }

    func updateSelectionAppearance() {
        layer.borderWidth = isSelected ? 1.5 : 0
    }

    func setRenderScale(_ scale: CGFloat) {
        func apply(_ view: UIView) {
            view.contentScaleFactor = scale
            view.subviews.forEach(apply)
        }
        apply(self)
    }

    /// A small round handle that moves or resizes the element.
    func makeHandle(systemImage: String, action: Selector) -> UIView {
        let handle = UIImageView(image: UIImage(systemName: systemImage))
        handle.tintColor = .white
        handle.contentMode = .center
        handle.backgroundColor = .systemBlue
        handle.layer.cornerRadius = 13
        handle.frame.size = CGSize(width: 26, height: 26)
        handle.isUserInteractionEnabled = true
        handle.isHidden = true
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: action))
        addSubview(handle)
        return handle
    }

    /// Drag translation in canvas coordinates.
    func takeTranslation(_ gesture: UIPanGestureRecognizer) -> CGPoint {
        guard let layerView else { return .zero }
        let translation = gesture.translation(in: layerView)
        gesture.setTranslation(.zero, in: layerView)
        return translation
    }
}
