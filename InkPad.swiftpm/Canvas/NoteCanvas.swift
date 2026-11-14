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
        // The note keeps its pages stacked down the screen; the canvas may
        // show them across instead (Settings › Scrolling Direction).
        let axis = controller.axis
        context.coordinator.axis = axis
        let display = axis.displayBackground(background)
        host.canvas.drawing = ScrollAxis.toDisplay(drawing: initialContent.drawing, stored: background, display: display)
        host.elementLayer.imageDirectory = initialContent.imageDirectory
        host.elementLayer.load(ScrollAxis.toDisplay(elements: initialContent.metadata.elements ?? [], stored: background, display: display))
        // Connect change reporting after loading so loading is not reported as an edit.
        host.canvas.delegate = context.coordinator
        context.coordinator.host = host
        host.onVisiblePageChange = { [weak controller] current, count in
            // May be reported during a SwiftUI update; publish afterwards.
            DispatchQueue.main.async {
                controller?.pageDidChange(current: current, count: count)
            }
        }
        host.fingerGestures.onTrigger = { [weak controller] trigger in
            guard let controller = controller else { return nil }
            return controller.perform(GestureSettingsStore.shared.action(for: trigger))
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
        // The direction is fixed while the note is open: changing it in
        // Settings applies to the notes opened next.
        host.configure(context.coordinator.axis.displayBackground(background))
    }

    static func dismantleUIView(_ host: NoteCanvasHostView, coordinator: Coordinator) {
        host.canvas.delegate = nil
        coordinator.controller.detach(host)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: CanvasController
        weak var host: NoteCanvasHostView?
        /// The direction the pages run in this open note.
        var axis: ScrollAxis = .vertical

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
