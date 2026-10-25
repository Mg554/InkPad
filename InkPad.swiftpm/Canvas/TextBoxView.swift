import UIKit

/// How text boxes take their words: typed on the keyboard, or handwritten
/// with Apple Pencil and turned into text (Scribble). Applies to every box.
enum TextInputMode: String {
    case keyboard, pencil

    static let didChange = Notification.Name("InkPad.TextInputModeDidChange")
    private static let defaultsKey = "textBoxInput"

    static var current: TextInputMode {
        TextInputMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .keyboard
    }

    static func set(_ mode: TextInputMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func toggle() {
        set(current == .keyboard ? .pencil : .keyboard)
    }

    /// The button that switches to the other mode.
    var switchSymbol: String { self == .keyboard ? "pencil.and.scribble" : "keyboard" }
    var switchLabel: String { self == .keyboard ? "Write with Apple Pencil" : "Type with Keyboard" }
}

/// An editable rich-text box. Height follows the text; width is resizable.
///
/// With the keyboard mode, tapping a box with Apple Pencil shows the
/// keyboard like a finger does (Scribble is turned off for the box). With the
/// pencil mode the keyboard stays hidden and handwriting becomes text.
final class TextBoxView: PageElementView, UITextViewDelegate, UIScribbleInteractionDelegate {
    let textView = UITextView()
    private var moveHandle: UIView!
    private var resizeHandle: UIView!
    /// Editing ends and begins again to bring the keyboard up; the box must
    /// not be removed as empty in between.
    private var isRefocusing = false

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
        textView.addInteraction(UIScribbleInteraction(delegate: self))
        addSubview(textView)
        applyInputMode()
        NotificationCenter.default.addObserver(self, selector: #selector(inputModeDidChange), name: TextInputMode.didChange, object: nil)

        moveHandle = makeHandle(systemImage: "arrow.up.and.down.and.arrow.left.and.right", action: #selector(handleMove(_:)))
        resizeHandle = makeHandle(systemImage: "arrow.left.and.right", action: #selector(handleResize(_:)))
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

    // MARK: Keyboard or Apple Pencil

    @objc private func inputModeDidChange() {
        applyInputMode()
    }

    private func applyInputMode() {
        let mode = TextInputMode.current
        // An empty input view keeps the keyboard away while the box is
        // still being edited, so handwriting goes into it.
        textView.inputView = mode == .pencil ? UIView(frame: .zero) : nil
        let switchItem = UIBarButtonItem(
            image: UIImage(systemName: mode.switchSymbol),
            style: .plain,
            target: self,
            action: #selector(switchInputMode)
        )
        switchItem.accessibilityLabel = mode.switchLabel
        textView.inputAssistantItem.trailingBarButtonGroups = [
            UIBarButtonItemGroup(barButtonItems: [switchItem], representativeItem: nil),
        ]
        if textView.isFirstResponder {
            textView.reloadInputViews()
        }
    }

    /// Brings up the keyboard. After a tap with Apple Pencil iPadOS keeps the
    /// keyboard hidden (it expects handwriting); editing again from a finger
    /// tap on a button shows it.
    func showKeyboard() {
        if TextInputMode.current == .pencil {
            TextInputMode.set(.keyboard)
        }
        guard textView.isFirstResponder else {
            textView.becomeFirstResponder()
            return
        }
        isRefocusing = true
        textView.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.textView.becomeFirstResponder()
            self?.isRefocusing = false
        }
    }

    @objc private func switchInputMode() {
        TextInputMode.toggle()
        layerView?.onTextStateChange?()
    }

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        TextInputMode.current == .pencil
    }

    // MARK: Gestures

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        let translation = takeTranslation(gesture)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        let translation = takeTranslation(gesture)
        frame.size.width = max(TextBoxStyle.minimumWidth, frame.width + translation.x)
        fitHeight()
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        layerView?.selectElement(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        fitHeight()
        layerView?.elementsDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        layerView?.onTextStateChange?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard !isRefocusing else { return }
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
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        resizeHandle = makeHandle(systemImage: "arrow.up.left.and.arrow.down.right", action: #selector(handleResize(_:)))
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

    @objc private func handleTap() {
        layerView?.endEditing(true)
        layerView?.selectElement(self)
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
        let translation = takeTranslation(gesture)
        let aspect = frame.height / max(frame.width, 1)
        let width = max(40, frame.width + translation.x)
        frame.size = CGSize(width: width, height: width * aspect)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }
}
