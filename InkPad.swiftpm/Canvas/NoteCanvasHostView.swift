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
    /// Above the ink: the lasso line and selection box.
    let selectionOverlay = SelectionOverlayView()
    private(set) var lasso: LassoSelection!
    private var isLassoMode = false
    private var savedPanTouchTypes: [NSNumber]?
    private var savedPanMinimumTouches = 1
    private let pageBackground = PageBackgroundView()
    private var background: NoteBackground?
    private var fitScale: CGFloat = 0
    private lazy var textTap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))
    private var suspendedRecognizers: [UIGestureRecognizer] = []

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
        addSubview(selectionOverlay)
        lasso = LassoSelection(host: self, overlay: selectionOverlay)
    }

    /// In lasso mode the pencil (or a finger, with finger drawing on) draws a
    /// selection instead of ink; scrolling moves to fingers (or two fingers).
    func setLassoMode(_ isOn: Bool) {
        let pencilOnly = canvas.drawingPolicy == .pencilOnly
        if isOn {
            if !isLassoMode {
                savedPanTouchTypes = canvas.panGestureRecognizer.allowedTouchTypes
                savedPanMinimumTouches = canvas.panGestureRecognizer.minimumNumberOfTouches
            }
            canvas.panGestureRecognizer.allowedTouchTypes = pencilOnly
                ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                : (savedPanTouchTypes ?? canvas.panGestureRecognizer.allowedTouchTypes)
            canvas.panGestureRecognizer.minimumNumberOfTouches = pencilOnly ? 1 : 2
        } else if isLassoMode {
            if let savedPanTouchTypes { canvas.panGestureRecognizer.allowedTouchTypes = savedPanTouchTypes }
            canvas.panGestureRecognizer.minimumNumberOfTouches = savedPanMinimumTouches
        }
        isLassoMode = isOn
        lasso.setEnabled(isOn, pencilOnly: pencilOnly)
        if !elementLayer.isInteractive {
            canvas.drawingGestureRecognizer.isEnabled = !isOn
        }
    }

    /// Re-applies lasso touch settings after "Draw with Finger" changes.
    func refreshLassoMode() {
        if isLassoMode { setLassoMode(true) }
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
    ///
    /// PencilKit's own taps (its Select All / Paste / Insert Space menu) are
    /// switched off meanwhile; otherwise they show that menu and make our tap
    /// wait for them. Only scrolling, zooming and our tap stay active.
    func setTextMode(_ isOn: Bool) {
        guard isOn != elementLayer.isInteractive else { return }
        elementLayer.isInteractive = isOn
        textTap.isEnabled = isOn
        if isOn {
            let kept: [UIGestureRecognizer] = [canvas.panGestureRecognizer, textTap] + [canvas.pinchGestureRecognizer].compactMap { $0 }
            suspendedRecognizers = Self.gestureRecognizers(in: canvas).filter { recognizer in
                recognizer.isEnabled && !kept.contains { $0 === recognizer }
            }
            suspendedRecognizers.forEach { $0.isEnabled = false }
        } else {
            suspendedRecognizers.forEach { $0.isEnabled = true }
            suspendedRecognizers = []
        }
        canvas.drawingGestureRecognizer.isEnabled = !isOn
    }

    private static func gestureRecognizers(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap { gestureRecognizers(in: $0) }
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
            elementLayer.selectElement(nil)
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
        for view in [pageBackground, elementLayer, selectionOverlay] as [UIView] {
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
        selectionOverlay.center = center
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
