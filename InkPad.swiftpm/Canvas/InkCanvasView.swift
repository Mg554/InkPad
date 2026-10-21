import PencilKit
import UIKit

/// A PencilKit canvas laid out as a vertical stack of pages that fits the
/// screen width and can be pinch-zoomed.
final class InkCanvasView: PKCanvasView {
    private let pageBackground = PageBackgroundView()
    private var pageCount = 1
    private var fitScale: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Paper is always white, so keep ink colors in their light-mode form.
        overrideUserInterfaceStyle = .light
        backgroundColor = UIColor(white: 0.88, alpha: 1)
        isOpaque = false
        alwaysBounceVertical = true
        insertSubview(pageBackground, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(template: PageTemplate, pageCount: Int) {
        pageBackground.configure(template: template, pageCount: pageCount)
        guard pageCount != self.pageCount else { return }
        self.pageCount = pageCount
        updateContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sendSubviewToBack(pageBackground)

        let newFitScale = bounds.width / PageLayout.pageSize.width
        guard newFitScale > 0, abs(newFitScale - fitScale) > 0.0001 else { return }
        // Keep "fit to width" across rotation unless the user zoomed in.
        let wasFitted = fitScale == 0 || abs(zoomScale - fitScale) < 0.0001
        fitScale = newFitScale
        minimumZoomScale = newFitScale
        maximumZoomScale = newFitScale * 5
        if wasFitted || zoomScale < newFitScale {
            zoomScale = newFitScale
        }
        updateContentSize()
    }

    /// Sizes the scrollable area and the page background for the current zoom.
    func updateContentSize() {
        let size = PageLayout.contentSize(pageCount: pageCount)
        let zoom = zoomScale
        contentSize = CGSize(width: size.width * zoom, height: size.height * zoom)
        pageBackground.transform = .identity
        pageBackground.bounds = CGRect(origin: .zero, size: size)
        pageBackground.center = CGPoint(x: size.width * zoom / 2, y: size.height * zoom / 2)
        pageBackground.transform = CGAffineTransform(scaleX: zoom, y: zoom)
    }
}
