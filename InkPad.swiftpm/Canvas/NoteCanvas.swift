import PencilKit
import SwiftUI

/// SwiftUI wrapper around `NoteCanvasHostView`.
struct NoteCanvas: UIViewRepresentable {
    /// Only read when the canvas is created; afterwards the canvas owns the drawing.
    let initialDrawing: PKDrawing
    let background: NoteBackground
    let pencilOnly: Bool
    let controller: CanvasController
    let palette: ToolPalette
    let onDrawingChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> NoteCanvasHostView {
        let host = NoteCanvasHostView()
        host.canvas.drawing = initialDrawing
        // Set the delegate after loading so the initial drawing is not reported as an edit.
        host.canvas.delegate = context.coordinator
        context.coordinator.host = host
        host.onVisiblePageChange = { [weak controller] current, count in
            // May be reported during a SwiftUI update; publish afterwards.
            DispatchQueue.main.async {
                controller?.pageDidChange(current: current, count: count)
            }
        }
        controller.attach(host, palette: palette)
        return host
    }

    func updateUIView(_ host: NoteCanvasHostView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        host.canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        host.configure(background)
    }

    static func dismantleUIView(_ host: NoteCanvasHostView, coordinator: Coordinator) {
        host.canvas.delegate = nil
        coordinator.controller.detach(host)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController
        var onDrawingChange: (PKDrawing) -> Void
        weak var host: NoteCanvasHostView?

        init(controller: CanvasController, onDrawingChange: @escaping (PKDrawing) -> Void) {
            self.controller = controller
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChange(canvasView.drawing)
            controller.refreshUndoState()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            host?.updateScrollPosition()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.updateZoomGeometry()
        }
    }
}
