import UIKit

/// An editable rich-text box. Height follows the text; width is resizable.
final class TextBoxView: PageElementView, UITextViewDelegate {
    let textView = UITextView()
    private var moveHandle: UIView!
    private var resizeHandle: UIView!

    init(id: UUID, frame: CGRect, text: NSAttributedString) {
        super.init(id: id, frame: frame)
        let padding = TextBoxStyle.padding
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        textView.textContainer.lineFragmentPadding = 0
        textView.allowsEditingTextAttributes = true
        textView.attributedText = text
        textView.typingAttributes = text.length > 0
            ? text.attributes(at: text.length - 1, effectiveRange: nil)
            : TextBoxStyle.defaultAttributes
        textView.delegate = self
        addSubview(textView)

        moveHandle = makeHandle(systemImage: "arrow.up.and.down.and.arrow.left.and.right", action: #selector(move(_:)))
        resizeHandle = makeHandle(systemImage: "arrow.left.and.right", action: #selector(resize(_:)))
        fitHeight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        moveHandle.center = CGPoint(x: 13, y: -15)
        resizeHandle.center = CGPoint(x: bounds.width + 15, y: bounds.height / 2)
    }

    // Handles sit just outside the box.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isSelected, moveHandle.frame.contains(point) || resizeHandle.frame.contains(point) {
            return true
        }
        return super.point(inside: point, with: event)
    }

    override func updateSelectionAppearance() {
        super.updateSelectionAppearance()
        moveHandle.isHidden = !isSelected
        resizeHandle.isHidden = !isSelected
    }

    override func makeElement() -> PageElement? {
        guard let rtf = TextBoxStyle.rtfData(from: textView.attributedText) else { return nil }
        return PageElement(id: id, frame: frame, content: .text(rtf: rtf))
    }

    var isEmpty: Bool {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func fitHeight() {
        let fitting = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let height = max(fitting.height.rounded(.up), 44)
        if abs(height - frame.height) > 0.5 {
            frame.size.height = height
        }
    }

    // MARK: Gestures

    @objc private func move(_ gesture: UIPanGestureRecognizer) {
        let translation = takeTranslation(gesture)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        let translation = takeTranslation(gesture)
        frame.size.width = max(TextBoxStyle.minimumWidth, frame.width + translation.x)
        fitHeight()
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        layerView?.select(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        fitHeight()
        layerView?.elementsDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        layerView?.onTextStateChange?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if isEmpty {
            layerView?.remove(self)
        } else {
            layerView?.elementsDidChange()
        }
    }
}

/// A placed image. Drag to move; the corner handle resizes, keeping its shape.
final class ImageElementView: PageElementView {
    let file: String
    private let imageView = UIImageView()
    private var resizeHandle: UIView!

    init(id: UUID, frame: CGRect, file: String, image: UIImage?) {
        self.file = file
        super.init(id: id, frame: frame)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.image = image ?? UIImage(systemName: "photo")
        imageView.tintColor = .secondaryLabel
        addSubview(imageView)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(move(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        resizeHandle = makeHandle(systemImage: "arrow.up.left.and.arrow.down.right", action: #selector(resize(_:)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizeHandle.center = CGPoint(x: bounds.width, y: bounds.height)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isSelected, resizeHandle.frame.contains(point) {
            return true
        }
        return super.point(inside: point, with: event)
    }

    override func updateSelectionAppearance() {
        super.updateSelectionAppearance()
        resizeHandle.isHidden = !isSelected
    }

    override func makeElement() -> PageElement? {
        PageElement(id: id, frame: frame, content: .image(file: file))
    }

    @objc private func tap() {
        layerView?.endEditing(true)
        layerView?.select(self)
    }

    @objc private func move(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            layerView?.endEditing(true)
            layerView?.select(self)
        }
        let translation = takeTranslation(gesture)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        let translation = takeTranslation(gesture)
        let aspect = frame.height / max(frame.width, 1)
        let width = max(40, frame.width + translation.x)
        frame.size = CGSize(width: width, height: width * aspect)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }
}
