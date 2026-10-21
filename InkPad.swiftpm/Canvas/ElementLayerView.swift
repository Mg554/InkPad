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

    private(set) weak var selected: PageElementView?
    private var renderScale: CGFloat = 2

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
            switch element.content {
            case let .text(rtf):
                let text = TextBoxStyle.attributedString(fromRTF: rtf) ?? NSAttributedString()
                add(TextBoxView(id: element.id, frame: element.frame, text: text))
            case let .image(file):
                guard isPlainFileName(file),
                      let directory = imageDirectory,
                      let image = UIImage(contentsOfFile: directory.appendingPathComponent(file).path)
                else {
                    // Keep the reference so a missing file is not silently dropped on save.
                    add(ImageElementView(id: element.id, frame: element.frame, file: file, image: nil))
                    continue
                }
                add(ImageElementView(id: element.id, frame: element.frame, file: file, image: image))
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

    func addImage(file: String, image: UIImage, pixelSize: CGSize, centeredAt center: CGPoint) {
        let maxWidth = PageLayout.pageWidth * 0.6
        let width = min(maxWidth, pixelSize.width / 2)
        let height = width * pixelSize.height / max(pixelSize.width, 1)
        let frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let view = ImageElementView(id: UUID(), frame: frame, file: file, image: image)
        add(view)
        selectElement(view)
        elementsDidChange()
    }

    private func add(_ view: PageElementView) {
        view.layerView = self
        addSubview(view)
        view.setRenderScale(renderScale)
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
        guard let selected else { return }
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

    /// Re-rasterizes text for the current zoom so it stays sharp.
    func setRenderScale(_ scale: CGFloat) {
        renderScale = scale
        for case let view as PageElementView in subviews {
            view.setRenderScale(scale)
        }
    }
}

/// Base class for a movable element on the page.
class PageElementView: UIView {
    let id: UUID
    weak var layerView: ElementLayerView?

    var isSelected = false {
        didSet { updateSelectionAppearance() }
    }

    init(id: UUID, frame: CGRect) {
        self.id = id
        super.init(frame: frame)
        layer.borderColor = UIColor.systemBlue.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func makeElement() -> PageElement? { nil }

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
