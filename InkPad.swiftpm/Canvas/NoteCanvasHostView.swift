import PencilKit
import UIKit

/// Stacks three layers that zoom and scroll together:
/// page background (bottom), text boxes and images, and a transparent
/// PencilKit canvas (top), which owns scrolling and zooming.
///
/// The background and elements are siblings behind the canvas rather than
/// canvas subviews: PencilKit paints its own background over anything
/// inserted beneath its ink. They follow the canvas's zoom and scroll instead.
final class NoteCanvasHostView: UIView {
    let canvas = PKCanvasView()
    let elementLayer = ElementLayerView()
    private let pageBackground = PageBackgroundView()
    private var background: NoteBackground?
    private var fitScale: CGFloat = 0
    private lazy var textTap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))

    /// Reports the page in the middle of the screen and the page count.
    var onVisiblePageChange: ((_ current: Int, _ count: Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Ink colors keep their light-mode form on every paper.
        overrideUserInterfaceStyle = .light
        backgroundColor = UIColor(white: 0.88, alpha: 1)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        textTap.isEnabled = false
        canvas.addGestureRecognizer(textTap)

        addSubview(pageBackground)
        addSubview(elementLayer)
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

    /// In text mode the pencil and fingers edit text boxes and images instead of drawing.
    func setTextMode(_ isOn: Bool) {
        elementLayer.isInteractive = isOn
        textTap.isEnabled = isOn
        canvas.drawingGestureRecognizer.isEnabled = !isOn
    }

    // Elements are below the canvas, so route touches to them in text mode.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if elementLayer.isInteractive,
           let hit = elementLayer.hitTest(convert(point, to: elementLayer), with: event) {
            return hit
        }
        return super.hitTest(point, with: event)
    }

    @objc private func handleTextTap(_ gesture: UITapGestureRecognizer) {
        if elementLayer.selected != nil {
            elementLayer.endEditing(true)
            elementLayer.select(nil)
            return
        }
        let point = gesture.location(in: elementLayer)
        guard let rects = background?.layout.pageRects, rects.contains(where: { $0.contains(point) }) else { return }
        elementLayer.addTextBox(at: point)
    }

    // MARK: Layout

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
            zoomDidEnd()
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
        for view in [pageBackground, elementLayer] as [UIView] {
            view.transform = .identity
            view.bounds = CGRect(origin: .zero, size: size)
            view.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        }
        updateScrollPosition()
    }

    /// Call when the canvas scrolls.
    func updateScrollPosition() {
        let size = pageBackground.bounds.size
        let zoom = canvas.zoomScale
        let offset = canvas.contentOffset
        let center = CGPoint(x: size.width * zoom / 2 - offset.x, y: size.height * zoom / 2 - offset.y)
        pageBackground.center = center
        elementLayer.center = center
        reportVisiblePage()
    }

    /// Call when a pinch ends: re-rasterize text for the new zoom.
    func zoomDidEnd() {
        let screenScale = window?.screen.scale ?? 2
        elementLayer.setRenderScale(min(screenScale * canvas.zoomScale, 6))
    }

    // MARK: Pages

    func scrollToPage(_ index: Int) {
        guard let rects = background?.layout.pageRects, rects.indices.contains(index) else { return }
        let inset = canvas.adjustedContentInset
        let zoom = canvas.zoomScale
        let maxY = max(canvas.contentSize.height + inset.bottom - canvas.bounds.height, -inset.top)
        let y = min(rects[index].minY * zoom - inset.top, maxY)
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: y), animated: false)
    }

    /// The middle of the visible area, in canvas coordinates.
    var visibleCenter: CGPoint {
        convert(CGPoint(x: bounds.midX, y: bounds.midY), to: elementLayer)
    }

    private func reportVisiblePage() {
        guard let rects = background?.layout.pageRects, !rects.isEmpty, canvas.zoomScale > 0 else { return }
        let middleY = (canvas.contentOffset.y + canvas.bounds.height / 2) / canvas.zoomScale
        let current = rects.lastIndex { $0.minY <= middleY } ?? 0
        onVisiblePageChange?(current, rects.count)
    }
}
