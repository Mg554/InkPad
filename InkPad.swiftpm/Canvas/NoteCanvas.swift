import PencilKit
import SwiftUI

/// SwiftUI wrapper around `InkCanvasView`.
struct NoteCanvas: UIViewRepresentable {
    /// Only read when the canvas is created; afterwards the canvas owns the drawing.
    let initialDrawing: PKDrawing
    let template: PageTemplate
    let pageCount: Int
    let pencilOnly: Bool
    let controller: CanvasController
    let onDrawingChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> InkCanvasView {
        let canvas = InkCanvasView()
        canvas.drawing = initialDrawing
        // Set the delegate after loading so the initial drawing is not reported as an edit.
        canvas.delegate = context.coordinator
        controller.attach(canvas)
        return canvas
    }

    func updateUIView(_ canvas: InkCanvasView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        canvas.configure(template: template, pageCount: pageCount)
    }

    static func dismantleUIView(_ canvas: InkCanvasView, coordinator: Coordinator) {
        canvas.delegate = nil
        coordinator.controller.detach(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController
        var onDrawingChange: (PKDrawing) -> Void

        init(controller: CanvasController, onDrawingChange: @escaping (PKDrawing) -> Void) {
            self.controller = controller
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChange(canvasView.drawing)
            controller.refreshUndoState()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? InkCanvasView)?.updateContentSize()
        }
    }
}
