import PencilKit
import SwiftUI

/// Lets SwiftUI toolbar buttons drive the UIKit canvas: undo/redo and the
/// floating PencilKit tool palette.
@MainActor
final class CanvasController: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var isToolPickerVisible = true {
        didSet { applyToolPickerVisibility() }
    }

    private weak var canvas: PKCanvasView?
    private let toolPicker = PKToolPicker()

    func attach(_ canvas: PKCanvasView) {
        self.canvas = canvas
        toolPicker.addObserver(canvas)
        // The canvas must be in a window before it can become first responder.
        DispatchQueue.main.async { [weak self] in
            self?.applyToolPickerVisibility()
            self?.refreshUndoState()
        }
    }

    func detach(_ canvas: PKCanvasView) {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        toolPicker.removeObserver(canvas)
        if self.canvas === canvas {
            self.canvas = nil
        }
    }

    func undo() {
        canvas?.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvas?.undoManager?.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }

    private func applyToolPickerVisibility() {
        guard let canvas else { return }
        toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvas)
        if isToolPickerVisible {
            canvas.becomeFirstResponder()
        }
    }
}
