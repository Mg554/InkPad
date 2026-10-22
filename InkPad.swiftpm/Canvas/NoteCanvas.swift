import PencilKit
import SwiftUI

/// SwiftUI wrapper around `NoteCanvasHostView`.
struct NoteCanvas: UIViewRepresentable {
    /// Only read when the canvas is created; afterwards the views own the content.
    let initialContent: NoteContent
    let background: NoteBackground
    let pencilOnly: Bool
    let controller: CanvasController
    let palette: ToolPalette

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> NoteCanvasHostView {
        let host = NoteCanvasHostView()
        host.canvas.drawing = initialContent.drawing
        host.elementLayer.imageDirectory = initialContent.imageDirectory
        host.elementLayer.load(initialContent.metadata.elements ?? [])
        // Connect change reporting after loading so loading is not reported as an edit.
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
        let policy: PKCanvasViewDrawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if host.canvas.drawingPolicy != policy {
            host.canvas.drawingPolicy = policy
            host.refreshLassoMode()
        }
        host.configure(background)
    }

    static func dismantleUIView(_ host: NoteCanvasHostView, coordinator: Coordinator) {
        host.canvas.delegate = nil
        coordinator.controller.detach(host)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController
        weak var host: NoteCanvasHostView?

        init(controller: CanvasController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.contentDidChange()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            host?.updateScrollPosition()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            host?.updateZoomGeometry()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            host?.zoomDidEnd()
        }
    }
}
