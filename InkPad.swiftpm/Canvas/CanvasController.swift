import PencilKit
import SwiftUI

/// Lets SwiftUI controls drive the UIKit canvas: tools, undo/redo, the
/// ruler, page navigation, text boxes and images.
@MainActor
final class CanvasController: NSObject, ObservableObject {
    enum Selection: Equatable {
        case text
        case image
    }

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 1
    @Published private(set) var selection: Selection?
    /// Bumped after formatting changes so the toolbar re-reads the text state.
    @Published private(set) var formattingRevision = 0
    @Published var isRulerActive = false {
        didSet { host?.canvas.isRulerActive = isRulerActive }
    }

    /// Called after every change to ink, text boxes or images.
    var onEdit: (() -> Void)?
    /// Called when ink from the open recording is tapped, with when it was written.
    var onInkTapped: ((Date) -> Void)?
    /// Lasso › Think: the selected writing as text, and where it is.
    var onThink: ((String, CGRect) -> Void)?
    /// Lasso › Remind Me: the selected writing as text.
    var onRemind: ((String) -> Void)?
    /// Lasso › Text from Area: a picture of the area and where it is.
    var onReadArea: ((UIImage, CGRect) -> Void)?
    /// Lasso › Send to Notebook: a picture of the area, and where it is.
    var onSendToNotebook: ((UIImage, CGRect) -> Void)? {
        didSet {
            guard onSendToNotebook != nil else {
                host?.lasso.onSendArea = nil
                return
            }
            host?.lasso.onSendArea = { [weak self] image, rect in self?.onSendToNotebook?(image, rect) }
        }
    }

    private weak var host: NoteCanvasHostView?
    private weak var palette: ToolPalette?
    // Kept when the canvas goes away, so a final save still has the content.
    private var lastDrawing: PKDrawing?
    private var lastElements: [PageElement]?
    /// The drawing when the current touch began, to undo a snap.
    private var drawingAtTouch: PKDrawing?
    /// Set when a touch ends; the next added stroke is the one just drawn.
    private var expectsNewStroke = false
    private var isReplacingStroke = false
    /// The eraser removed ink during the current touch.
    private var didEraseDuringTouch = false
    /// The touch ended before PencilKit reported its erase.
    private var awaitsEraseAfterTouch = false
    /// Audio playback replay, kept so a new canvas view picks it up.
    private var replayInterval: DateInterval?
    private var replayNow = Date.distantPast
    /// The first stroke not yet leveled by Refine Handwriting.
    private var refineStart: Int?
    private var refineTask: Task<Void, Never>?
    /// Living Notes: the open note, and strokes not yet read for concepts.
    var livingNoteID: UUID?
    /// Called with a concept key when a Living Notes bubble is tapped.
    var onConcept: ((String) -> Void)?
    private var livingStart: Int?
    private var livingTask: Task<Void, Never>?

    var drawing: PKDrawing? { host?.canvas.drawing ?? lastDrawing }
    var elements: [PageElement]? { host?.elementLayer.elements ?? lastElements }

    func attach(_ host: NoteCanvasHostView, palette: ToolPalette) {
        self.host = host
        self.palette = palette
        host.canvas.isRulerActive = isRulerActive
        host.elementLayer.onChange = { [weak self] in self?.contentDidChange() }
        host.lasso.onChange = { [weak self] in self?.contentDidChange() }
        host.lasso.onThink = { [weak self] text, rect in self?.onThink?(text, rect) }
        host.lasso.onRemind = { [weak self] text in self?.onRemind?(text) }
        host.lasso.onReadArea = { [weak self] image, rect in self?.onReadArea?(image, rect) }
        if onSendToNotebook != nil {
            host.lasso.onSendArea = { [weak self] image, rect in self?.onSendToNotebook?(image, rect) }
        }
        host.elementLayer.onTextStateChange = { [weak self] in
            self?.formattingRevision += 1
        }
        host.elementLayer.onSelectionChange = { [weak self] view in
            self?.selection = view is TextBoxView ? .text : view is ImageElementView ? .image : nil
        }
        let holdTracker = StrokeHoldTracker()
        holdTracker.coordinateView = host.elementLayer
        holdTracker.onTouchBegan = { [weak self, weak host] in
            self?.drawingAtTouch = host?.canvas.drawing
            self?.refineTask?.cancel()
            self?.livingTask?.cancel()
            self?.expectsNewStroke = false
            self?.didEraseDuringTouch = false
            self?.awaitsEraseAfterTouch = false
        }
        holdTracker.onHold = { [weak self] points in
            self?.snapHeldStroke(points)
        }
        holdTracker.onTouchEnded = { [weak self] in
            // PencilKit may add the stroke before or after this; handle both.
            guard let self else { return }
            self.expectsNewStroke = !self.evenOutNewStroke()
            self.eraseTouchEnded()
        }
        host.canvas.addGestureRecognizer(holdTracker)
        host.onInkTapped = { [weak self] date in self?.onInkTapped?(date) }
        host.livingOverlay.onTap = { [weak self] key in self?.onConcept?(key) }
        if replayInterval != nil {
            host.setReplay(replayInterval, now: replayNow)
        }
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        host.canvas.addInteraction(pencilInteraction)
        applyTool()
        DispatchQueue.main.async { [weak self] in
            self?.refreshUndoState()
        }
    }

    func detach(_ host: NoteCanvasHostView) {
        guard self.host === host else { return }
        lastDrawing = host.canvas.drawing
        lastElements = host.elementLayer.elements
        self.host = nil
    }

    func contentDidChange() {
        if expectsNewStroke, !isReplacingStroke, evenOutNewStroke() {
            expectsNewStroke = false
        }
        if palette?.tool == .eraser {
            if awaitsEraseAfterTouch {
                returnFromEraser()
            } else {
                didEraseDuringTouch = true
            }
        }
        host?.inkDidChange()
        refreshUndoState()
        onEdit?()
    }

    func applyTool() {
        guard let host, let palette else { return }
        switch palette.tool {
        case .text: host.setMode(.text)
        case .lasso: host.setMode(.lasso)
        case .laser:
            host.laser.color = palette.style(for: .laser).selectedColor.uiColor
            host.laser.leavesTail = palette.laserLeavesTail
            host.setMode(.laser)
        default: host.setMode(.draw)
        }
        host.canvas.tool = palette.pkTool
    }

    // MARK: Eraser

    /// With "Back to Last Tool" on, returns to the previous tool once an erase
    /// is done. PencilKit may report the erase before or after the touch ends.
    private func eraseTouchEnded() {
        guard let palette, palette.tool == .eraser, palette.returnsAfterErasing else { return }
        if didEraseDuringTouch {
            returnFromEraser()
        } else {
            awaitsEraseAfterTouch = true
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.awaitsEraseAfterTouch = false
            }
        }
    }

    private func returnFromEraser() {
        didEraseDuringTouch = false
        awaitsEraseAfterTouch = false
        // Once PencilKit has finished with the touch.
        DispatchQueue.main.async { [weak self] in
            guard let self, let palette = self.palette, palette.tool == .eraser, palette.returnsAfterErasing else { return }
            palette.returnFromEraser()
            self.applyTool()
        }
    }

    // MARK: Undo

    func undo() {
        host?.canvas.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        host?.canvas.undoManager?.redo()
        refreshUndoState()
    }

    /// Publishes only real changes: every erase step and stroke calls this,
    /// and each publish re-renders the toolbar.
    func refreshUndoState() {
        let undo = host?.canvas.undoManager?.canUndo ?? false
        let redo = host?.canvas.undoManager?.canRedo ?? false
        if undo != canUndo { canUndo = undo }
        if redo != canRedo { canRedo = redo }
    }

    /// Called while the pencil rests at the end of a stroke: ends the stroke
    /// and puts a clean line or shape in its place, like Notability.
    private func snapHeldStroke(_ points: [CGPoint]) {
        guard let host, let palette, palette.snapsShapes, palette.tool.isInking,
              let before = drawingAtTouch, let tool = palette.pkTool as? PKInkingTool,
              let first = points.first, let last = points.last
        else { return }
        let shape: ShapeRecognizer.Shape
        if palette.tool == .highlighter {
            // Highlighting follows lines of text, so the highlighter always snaps straight.
            guard Math.distance(last.x - first.x, last.y - first.y) > 8 else { return }
            shape = .polyline([first, last], closed: false)
        } else {
            guard let recognized = ShapeRecognizer.recognize(points) else { return }
            shape = recognized
        }

        // Stop PencilKit's stroke; whether it keeps or drops it, ours replaces it.
        isReplacingStroke = true
        host.canvas.drawingGestureRecognizer.isEnabled = false
        host.canvas.drawingGestureRecognizer.isEnabled = true
        DispatchQueue.main.async { [weak self, weak host] in
            guard let self, let host else { return }
            var snapped = before
            snapped.strokes.append(ShapeRecognizer.stroke(for: shape, ink: tool.ink, width: tool.width))
            host.canvas.drawing = snapped
            host.canvas.undoManager?.registerUndo(withTarget: host.canvas) { canvas in
                canvas.drawing = before
            }
            self.expectsNewStroke = false
            self.isReplacingStroke = false
            self.contentDidChange()
        }
    }

    /// With pressure turned off for the tool, gives the new stroke an even
    /// width. Returns `true` once the new stroke has been handled.
    @discardableResult
    private func evenOutNewStroke() -> Bool {
        guard let host, let palette, let before = drawingAtTouch,
              host.canvas.drawing.strokes.count == before.strokes.count + 1,
              let stroke = host.canvas.drawing.strokes.last
        else { return false }
        guard palette.tool.isInking else { return true }
        let settings = HandwritingSettingsStore.shared.settings
        let flattens = palette.style(for: palette.tool).ignoresPressure(for: palette.tool)
        let smooths = settings.smooths && palette.tool != .highlighter
        if palette.tool != .highlighter {
            noteStrokeForRefining(at: host.canvas.drawing.strokes.count - 1, settings: settings)
            noteStrokeForLiving(at: host.canvas.drawing.strokes.count - 1)
        }
        guard flattens || smooths else { return true }
        var replacement = stroke
        if flattens {
            replacement = ShapeRecognizer.withoutPressure(replacement, width: palette.style(for: palette.tool).selectedWidth(for: palette.tool))
        }
        if smooths {
            replacement = HandwritingRefiner.smooth(replacement, strength: settings.smoothStrength)
        }
        var even = host.canvas.drawing
        even.strokes[even.strokes.count - 1] = replacement
        isReplacingStroke = true
        host.canvas.drawing = even
        isReplacingStroke = false
        return true
    }

    // MARK: Refine Handwriting

    /// Remembers a new stroke, and levels its line once the writer pauses.
    private func noteStrokeForRefining(at index: Int, settings: HandwritingSettings) {
        guard settings.straightens || settings.evensSize else { return }
        if refineStart == nil || refineStart! > index { refineStart = index }
        refineTask?.cancel()
        refineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settings.pause))
            guard !Task.isCancelled else { return }
            self?.refinePendingLines()
        }
    }

    // MARK: Living Notes

    /// After a pause, reads the new writing and shows bubbles for concepts
    /// other notes also talk about.
    private func noteStrokeForLiving(at index: Int) {
        let living = LivingNotes.shared
        guard let noteID = livingNoteID, living.settings.isOn(for: noteID), living.settings.inkBubbles else { return }
        if livingStart == nil || livingStart! > index { livingStart = index }
        livingTask?.cancel()
        livingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            await self?.readForLiving(noteID: noteID)
        }
    }

    private func readForLiving(noteID: UUID) async {
        guard let host, let start = livingStart, start < host.canvas.drawing.strokes.count else { return }
        livingStart = nil
        let strokes = Array(host.canvas.drawing.strokes[start...])
        let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let text = await Task.detached(priority: .utility) {
            MindSketchReader.readText(PKDrawing(strokes: strokes))
        }.value
        guard !text.isEmpty, !Task.isCancelled else { return }
        let concepts = LivingNotes.shared.knownConcepts(in: text, excluding: noteID).prefix(2)
        guard !concepts.isEmpty else { return }
        host.livingOverlay.show(concepts.map { ($0.key, $0.display, $0.otherNotes) }, at: CGPoint(x: bounds.maxX + 10, y: bounds.minY))
    }

    private func refinePendingLines() {
        guard let host, let start = refineStart else { return }
        refineStart = nil
        let drawing = host.canvas.drawing
        guard start < drawing.strokes.count else { return }
        let settings = HandwritingSettingsStore.shared.settings
        var strokes = drawing.strokes
        let fresh = Dictionary(uniqueKeysWithValues: (start..<strokes.count)
            .filter { strokes[$0].ink.inkType != .marker }
            .map { ($0, strokes[$0]) })
        var changed = false
        for line in HandwritingRefiner.lines(of: fresh) {
            let original = line.map { strokes[$0] }
            guard HandwritingRefiner.looksLikeWriting(original) else { continue }
            var refined = original
            if settings.straightens { refined = HandwritingRefiner.straighten(refined) }
            if settings.evensSize { refined = HandwritingRefiner.evenSize(refined) }
            for (index, (before, after)) in zip(line, zip(original, refined)) where before.transform != after.transform {
                strokes[index] = after
                changed = true
            }
        }
        guard changed else { return }
        var refined = drawing
        refined.strokes = strokes
        isReplacingStroke = true
        host.canvas.drawing = refined
        host.canvas.undoManager?.registerUndo(withTarget: host.canvas) { canvas in
            canvas.drawing = drawing
        }
        isReplacingStroke = false
        contentDidChange()
    }

    // MARK: Audio replay

    /// Fades ink written during `recording` after `time` into it, until
    /// playback reaches it; `nil` shows all ink normally.
    func showReplay(of recording: AudioRecording?, at time: TimeInterval) {
        replayInterval = recording?.interval
        replayNow = recording.map { $0.startDate.addingTimeInterval(time) } ?? .distantPast
        host?.setReplay(replayInterval, now: replayNow)
    }

    // MARK: Pages

    func pageDidChange(current: Int, count: Int) {
        if current != currentPage { currentPage = current }
        if count != pageCount { pageCount = count }
    }

    func scrollToPage(_ index: Int) {
        host?.scrollToPage(index)
    }

    // MARK: Text boxes and images

    var selectedTextView: UITextView? {
        (host?.elementLayer.selected as? TextBoxView)?.textView
    }

    func formatText(_ change: (UITextView) -> Void) {
        guard let textView = selectedTextView else { return }
        change(textView)
        formattingRevision += 1
    }

    /// Shows the keyboard for the selected text box.
    func showKeyboard() {
        (host?.elementLayer.selected as? TextBoxView)?.showKeyboard()
        formattingRevision += 1
    }

    /// Switches text boxes between typing and writing with Apple Pencil.
    func toggleTextInputMode() {
        TextInputMode.toggle()
        if TextInputMode.current == .keyboard {
            (host?.elementLayer.selected as? TextBoxView)?.showKeyboard()
        }
        formattingRevision += 1
    }

    func deleteSelectedElement() {
        host?.elementLayer.removeSelected()
    }

    /// Moves ink and elements below `y` by `delta` and removes what lies in
    /// `removing`, keeping content on its page when pages are inserted or deleted.
    func shiftContent(below y: CGFloat, by delta: CGFloat, removing: ClosedRange<CGFloat>?) {
        guard let host else { return }
        let move = CGAffineTransform(translationX: 0, y: delta)
        var strokes: [PKStroke] = []
        for var stroke in host.canvas.drawing.strokes {
            let middle = stroke.renderBounds.midY
            if let removing, removing.contains(middle) { continue }
            if middle > y { stroke.transform = stroke.transform.concatenating(move) }
            strokes.append(stroke)
        }
        host.canvas.drawing = PKDrawing(strokes: strokes)
        // Ink undo steps refer to the old positions.
        host.canvas.undoManager?.removeAllActions()
        host.elementLayer.shiftElements(below: y, by: delta, removing: removing)
        contentDidChange()
    }

    /// Moves ink and elements vertically; `offset` says how far content
    /// centered at a given y moves (used to reorder pages).
    func moveContent(by offset: (CGFloat) -> CGFloat) {
        guard let host else { return }
        var strokes = host.canvas.drawing.strokes
        for index in strokes.indices {
            let delta = offset(strokes[index].renderBounds.midY)
            guard delta != 0 else { continue }
            strokes[index].transform = strokes[index].transform
                .concatenating(CGAffineTransform(translationX: 0, y: delta))
        }
        host.canvas.drawing = PKDrawing(strokes: strokes)
        // Ink undo steps refer to the old positions.
        host.canvas.undoManager?.removeAllActions()
        host.elementLayer.moveElements(by: offset)
        contentDidChange()
    }

    /// Places text (an AI answer) on the page below `rect`.
    func placeText(_ text: NSAttributedString, below rect: CGRect) {
        host?.elementLayer.addTextBox(text, below: rect)
    }

    func insertImage(file: String, image: UIImage, pixelSize: CGSize, caption: NSAttributedString? = nil) {
        guard let host else { return }
        palette?.select(.text)
        applyTool()
        let frame = host.elementLayer.addImage(file: file, image: image, pixelSize: pixelSize, centeredAt: host.visibleCenter)
        if let caption { host.elementLayer.addTextBox(caption, below: frame) }
    }

    /// A text box in the middle of what is shown.
    func placeTextInView(_ text: NSAttributedString) {
        guard let host else { return }
        let center = host.visibleCenter
        host.elementLayer.addTextBox(text, below: CGRect(x: center.x - 240, y: center.y - 60, width: 480, height: 0))
    }
}

extension CanvasController: UIPencilInteractionDelegate {
    /// Apple Pencil (2nd generation / Pro) double-tap, following the system setting.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser, .switchPrevious:
            palette?.toggleEraser()
            applyTool()
        default:
            break
        }
    }
}
