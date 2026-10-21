import PencilKit
import SwiftUI

/// Lets SwiftUI controls drive the UIKit canvas: tools, undo/redo, the
/// ruler, and page navigation.
@MainActor
final class CanvasController: NSObject, ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var currentPage = 0
    @Published private(set) var pageCount = 1
    @Published var isRulerActive = false {
        didSet { host?.canvas.isRulerActive = isRulerActive }
    }

    private weak var host: NoteCanvasHostView?
    private weak var palette: ToolPalette?

    var drawing: PKDrawing? { host?.canvas.drawing }

    func attach(_ host: NoteCanvasHostView, palette: ToolPalette) {
        self.host = host
        self.palette = palette
        host.canvas.isRulerActive = isRulerActive
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        host.canvas.addInteraction(pencilInteraction)
        applyTool()
        DispatchQueue.main.async { [weak self] in
            self?.refreshUndoState()
        }
    }

    func detach(_ host: NoteCanvasHostView) {
        if self.host === host {
            self.host = nil
        }
    }

    func applyTool() {
        guard let host, let palette else { return }
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

    func pageDidChange(current: Int, count: Int) {
        if current != currentPage { currentPage = current }
        if count != pageCount { pageCount = count }
    }

    func scrollToPage(_ index: Int) {
        host?.scrollToPage(index)
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
