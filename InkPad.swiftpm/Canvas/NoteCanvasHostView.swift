import PencilKit
import UIKit

/// Hosts a transparent PencilKit canvas over the page background.
///
/// The background is a sibling behind the canvas rather than a canvas subview:
/// PencilKit paints its own background over anything inserted beneath its ink.
/// The background follows the canvas's zoom and scroll position instead.
final class NoteCanvasHostView: UIView {
    let canvas = PKCanvasView()
    private let pageBackground = PageBackgroundView()
    private var background: NoteBackground?
    private var fitScale: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Paper is always white, so keep ink colors in their light-mode form.
        overrideUserInterfaceStyle = .light
        backgroundColor = UIColor(white: 0.88, alpha: 1)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        addSubview(pageBackground)
        addSubview(canvas)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ background: NoteBackground) {
        guard background != self.background else { return }
        self.background = background
        pageBackground.configure(background)
        updateZoomGeometry()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds

        let newFitScale = bounds.width / PageLayout.pageWidth
        if newFitScale > 0, abs(newFitScale - fitScale) > 0.0001 {
            // Keep "fit to width" across rotation unless the user zoomed in.
            let wasFitted = fitScale == 0 || abs(canvas.zoomScale - fitScale) < 0.0001
            fitScale = newFitScale
            canvas.minimumZoomScale = newFitScale
            canvas.maximumZoomScale = newFitScale * 5
            if wasFitted || canvas.zoomScale < newFitScale {
                canvas.zoomScale = newFitScale
            }
        }
        updateZoomGeometry()
    }

    /// Call when the zoom scale or the pages change.
    func updateZoomGeometry() {
        let size = background?.layout.contentSize ?? PageLayout.templatePageSize
        let zoom = canvas.zoomScale
        let scaledSize = CGSize(width: size.width * zoom, height: size.height * zoom)
        if canvas.contentSize != scaledSize {
            canvas.contentSize = scaledSize
        }
        pageBackground.transform = .identity
        pageBackground.bounds = CGRect(origin: .zero, size: size)
        pageBackground.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        updateScrollPosition()
    }

    /// Call when the canvas scrolls.
    func updateScrollPosition() {
        let size = pageBackground.bounds.size
        let zoom = canvas.zoomScale
        let offset = canvas.contentOffset
        pageBackground.center = CGPoint(
            x: size.width * zoom / 2 - offset.x,
            y: size.height * zoom / 2 - offset.y
        )
    }
}
