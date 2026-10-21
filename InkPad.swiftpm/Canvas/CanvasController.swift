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

    private weak var host: NoteCanvasHostView?
    private weak var palette: ToolPalette?
    // Kept when the canvas goes away, so a final save still has the content.
    private var lastDrawing: PKDrawing?
    private var lastElements: [PageElement]?

    var drawing: PKDrawing? { host?.canvas.drawing ?? lastDrawing }
    var elements: [PageElement]? { host?.elementLayer.elements ?? lastElements }

    func attach(_ host: NoteCanvasHostView, palette: ToolPalette) {
        self.host = host
        self.palette = palette
        host.canvas.isRulerActive = isRulerActive
        host.elementLayer.onChange = { [weak self] in self?.contentDidChange() }
        host.elementLayer.onTextStateChange = { [weak self] in
            self?.formattingRevision += 1
        }
        host.elementLayer.onSelectionChange = { [weak self] view in
            self?.selection = view is TextBoxView ? .text : view is ImageElementView ? .image : nil
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
        refreshUndoState()
        onEdit?()
    }

    func applyTool() {
        guard let host, let palette else { return }
        host.setTextMode(palette.tool == .text)
        host.canvas.tool = palette.pkTool
    }

    func undo() {
        host?.canvas.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        host?.canvas.undoManager?.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = host?.canvas.undoManager?.canUndo ?? false
        canRedo = host?.canvas.undoManager?.canRedo ?? false
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

    func insertImage(file: String, image: UIImage, pixelSize: CGSize) {
        guard let host else { return }
        palette?.select(.text)
        applyTool()
        host.elementLayer.addImage(file: file, image: image, pixelSize: pixelSize, centeredAt: host.visibleCenter)
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
