import PencilKit
import UIKit

/// How InkPad's text fields take words: typed on the keyboard (Apple Pencil
/// taps open it too), or handwritten with Apple Pencil and turned into text
/// (Scribble). Applies everywhere; see `ScribbleGate`.
enum TextInputMode: String {
    case keyboard, pencil

    static let didChange = Notification.Name("InkPad.TextInputModeDidChange")
    static let defaultsKey = "textBoxInput"

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
/// keyboard like a finger does. With the pencil mode the keyboard stays
/// hidden and handwriting becomes text.
final class TextBoxView: PageElementView, UITextViewDelegate {
    let textView = UITextView()
    private var moveHandle: UIView!
    private var resizeHandle: UIView!
    /// Editing ends and begins again to bring the keyboard up; the box must
    /// not be removed as empty in between.
    private var isRefocusing = false
    /// Scribble can change the text many times per second. Measuring the
    /// height on every change makes pencil typing stutter, so coalesce it.
    private var fitScheduled = false
    /// "Show Keyboard" was asked for in this box, so bring up the keyboard
    /// here while still handwriting in the other boxes next time.
    private var showsKeyboardNow = false
    /// The small ink surface over this box in handwriting mode: writing on
    /// it becomes text, with any pen, not only an Apple Pencil.
    private var inkSurface: PKCanvasView?
    private var readHandwritingTask: Task<Void, Never>?
    private var isReadingHandwriting = false

    init(id: UUID, frame: CGRect, text: NSAttributedString, isLocked: Bool = false) {
        super.init(id: id, frame: frame, isLocked: isLocked)
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
        let display = BidiIsolation.displayReady(text)
        textView.attributedText = display
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
        moveHandle.isHidden = !isSelected || isElementLocked
        resizeHandle.isHidden = !isSelected || isElementLocked
    }

    override func makeElement() -> PageElement? {
        let stored = BidiIsolation.strippedAttributed(textView.attributedText)
        guard let rtf = TextBoxStyle.rtfData(from: stored) else { return nil }
        return PageElement(id: id, frame: frame, content: .text(rtf: rtf),
                           isLocked: isElementLocked ? true : nil, anchorTo: anchorTo)
    }

    var isEmpty: Bool {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func fitHeight() {
        let fitting = textView.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let height = max(fitting.height.rounded(.up), 44)
        let delta = height - frame.height
        if abs(delta) > 0.5 {
            frame.size.height = height
            layerView?.anchorDidResize(self, delta: delta)
        }
    }

    /// At most one height measurement per run loop, for pencil typing.
    private func fitHeightSoon() {
        guard !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fitScheduled = false
            self.fitHeight()
        }
    }

    /// Replaces `range` of the text with `string`, keeping the formatting
    /// of the text that was there (or the typing attributes when the box
    /// is empty), and selects the inserted text. Used by AI Rewrite.
    func replaceText(in range: NSRange, with string: String) {
        let current = textView.attributedText ?? NSAttributedString()
        let location = min(max(range.location, 0), current.length)
        let length = min(range.length, current.length - location)
        let clipped = NSRange(location: location, length: length)
        let attributes = clipped.length > 0
            ? current.attributes(at: clipped.location, effectiveRange: nil)
            : textView.typingAttributes
        let mutable = NSMutableAttributedString(attributedString: current)
        mutable.replaceCharacters(in: clipped, with: NSAttributedString(string: string, attributes: attributes))
        textView.attributedText = mutable
        textView.selectedRange = NSRange(location: clipped.location + (string as NSString).length, length: 0)
        fitHeight()
        textView.delegate?.textViewDidChange?(textView)
    }

    // MARK: Keyboard or Apple Pencil

    @objc private func inputModeDidChange() {
        // A new choice replaces any one-off keyboard request.
        showsKeyboardNow = false
        applyInputMode()
    }

    private func applyInputMode() {
        let mode = TextInputMode.current
        // An empty input view keeps the keyboard away while the box is
        // still being edited, so handwriting goes into it. It is left out
        // when this box was asked to show the keyboard.
        let hidesKeyboard = mode == .pencil && !showsKeyboardNow
        textView.inputView = hidesKeyboard ? UIView(frame: .zero) : nil
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
        updateHandwritingSurface()
    }

    /// Brings up the keyboard in this box. After a tap with Apple Pencil
    /// iPadOS keeps the keyboard hidden (it expects handwriting); editing
    /// again from a finger tap on a button shows it. The saved handwriting
    /// setting is left alone, so the next box writes again.
    func showKeyboard() {
        if TextInputMode.current == .pencil {
            showsKeyboardNow = true
            applyInputMode()
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

    // MARK: Handwriting that becomes text

    /// Writing on the page, then read on the iPad and typed into the box.
    /// iPadOS Scribble only answers an Apple Pencil, so the box keeps its
    /// own small ink surface: any pen, or a finger, writes on it and the
    /// writing turns into text when the pen lifts.
    private func updateHandwritingSurface() {
        let wantsInk = TextInputMode.current == .pencil && !showsKeyboardNow
        if wantsInk {
            guard inkSurface == nil else { return }
            let surface = PKCanvasView(frame: bounds)
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            surface.backgroundColor = .clear
            surface.isOpaque = false
            surface.isScrollEnabled = false
            surface.drawingPolicy = .anyInput
            surface.delegate = self
            surface.tool = PKInkingTool(.pen, color: UIColor(white: 0.08, alpha: 1), width: 2)
            addSubview(surface)
            inkSurface = surface
            return
        }
        readHandwritingTask?.cancel()
        readHandwritingTask = nil
        inkSurface?.removeFromSuperview()
        inkSurface = nil
    }

    /// Reads the writing a moment after the pen lifts, so a whole word or
    /// line is read together.
    private func scheduleHandwritingRead() {
        readHandwritingTask?.cancel()
        readHandwritingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            self?.readHandwriting()
        }
    }

    private func readHandwriting() {
        guard !isReadingHandwriting,
              let surface = inkSurface,
              !surface.drawing.strokes.isEmpty
        else { return }
        isReadingHandwriting = true
        let drawing = surface.drawing
        let readCount = drawing.strokes.count
        let region = bounds.union(drawing.bounds).insetBy(dx: -6, dy: -6)
        let picture = InkSnapshot.forReading(of: drawing, from: region)
        guard let image = picture.cgImage else {
            isReadingHandwriting = false
            return
        }
        Task { [weak self] in
            let lines = await Task.detached(priority: .userInitiated) {
                InkOCR.handwritingLines(in: image)
            }.value
            self?.finishHandwriting(lines, readCount: readCount)
        }
    }

    private func finishHandwriting(_ lines: [InkOCR.Line], readCount: Int) {
        isReadingHandwriting = false
        guard let surface = inkSurface else { return }
        let text = lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else {
            // The ink stays, so it can be written over or added to.
            CommandCenter.shared.say(tr("Nothing was read from that writing. Write larger or clearer, then try again."))
            return
        }
        insertHandwritten(text)
        // Only what was read leaves the surface; writing that came in
        // meanwhile stays and is read next.
        var left = surface.drawing
        let removed = min(readCount, left.strokes.count)
        if removed > 0 {
            left.strokes.removeFirst(removed)
        }
        surface.drawing = left
        if !left.strokes.isEmpty {
            scheduleHandwritingRead()
        }
    }

    private func insertHandwritten(_ text: String) {
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        let current = textView.text ?? ""
        let needsSpace = !current.isEmpty
            && !current.hasSuffix(" ")
            && !current.hasSuffix("\n")
        textView.insertText(needsSpace ? " " + text : text)
        fitHeight()
    }

    // MARK: Gestures

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        guard !isElementLocked else { return }
        let translation = takeTranslation(gesture)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        guard !isElementLocked else { return }
        let translation = takeTranslation(gesture)
        frame.size.width = max(TextBoxStyle.minimumWidth, frame.width + translation.x)
        fitHeight()
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        // The display-only bidi controls are removed before writing, so the
        // caret, Delete and Scribble work on the words alone.
        if let current = textView.attributedText, BidiIsolation.hasControls(current.string) {
            let ready = BidiIsolation.editingReady(current, selection: textView.selectedRange)
            textView.attributedText = ready.text
            textView.selectedRange = ready.selection
        }
        layerView?.selectElement(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        fitHeightSoon()
        layerView?.elementsDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        layerView?.onTextStateChange?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        textView.attributedText = BidiIsolation.displayReady(textView.attributedText ?? NSAttributedString())
        fitHeight()
        // Ending the keyboard request puts handwriting back for this box.
        guard !isRefocusing else { return }
        showsKeyboardNow = false
        applyInputMode()
        if isEmpty {
            layerView?.remove(self)
        } else {
            layerView?.elementsDidChange()
        }
    }
}

extension TextBoxView: PKCanvasViewDelegate {
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        // Typing into the box needs the caret, even though the pen writes
        // on the surface above it. An empty input view keeps the keyboard
        // away, so no keyboard covers the writing.
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        scheduleHandwritingRead()
    }
}

/// A placed image. Drag to move; the corner handle resizes, keeping its shape.
final class ImageElementView: PageElementView {
    let file: String
    private let imageView = UIImageView()
    private var resizeHandle: UIView!

    init(id: UUID, frame: CGRect, file: String, image: UIImage?, isLocked: Bool = false) {
        self.file = file
        super.init(id: id, frame: frame, isLocked: isLocked)
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
        resizeHandle.isHidden = !isSelected || isElementLocked
    }

    override func makeElement() -> PageElement? {
        PageElement(id: id, frame: frame, content: .image(file: file), isLocked: isElementLocked ? true : nil)
    }

    var image: UIImage? { imageView.image }

    @objc private func handleTap() {
        layerView?.endEditing(true)
        layerView?.selectElement(self)
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

    @objc private func handleResize(_ gesture: UIPanGestureRecognizer) {
        guard !isElementLocked else { return }
        let translation = takeTranslation(gesture)
        let aspect = frame.height / max(frame.width, 1)
        let width = max(40, frame.width + translation.x)
        frame.size = CGSize(width: width, height: width * aspect)
        if gesture.state == .ended { layerView?.elementsDidChange() }
    }
}
