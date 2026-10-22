import PencilKit
import UIKit

/// Stacks three layers that zoom and scroll together:
/// page background (bottom), text boxes and images, and a transparent
/// PencilKit canvas (top), which owns scrolling and zooming. During audio
/// playback a replay canvas sits above the ink (see `InkReplay`).
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
    private var replay: InkReplay!
    private var savedPanTouchTypes: [NSNumber]?
    private var savedPanMinimumTouches = 1
    private let pageBackground = PageBackgroundView()
    private var background: NoteBackground?
    private var fitScale: CGFloat = 0
    private lazy var textTap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))
    /// During playback, a finger tap on ink plays from when it was written.
    private lazy var seekTap = UITapGestureRecognizer(target: self, action: #selector(handleSeekTap(_:)))
    private var suspendedRecognizers: [UIGestureRecognizer] = []

    /// Reports the page in the middle of the screen and the page count.
    var onVisiblePageChange: ((_ current: Int, _ count: Int) -> Void)?
    /// Called when ink from the playing recording is tapped, with when it was written.
    var onInkTapped: ((Date) -> Void)?

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
        seekTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        seekTap.isEnabled = false
        canvas.addGestureRecognizer(seekTap)

        replay = InkReplay(canvas: canvas)
        addSubview(pageBackground)
        addSubview(elementLayer)
        addSubview(canvas)
        addSubview(replay.mirror)
        addSubview(selectionOverlay)
        lasso = LassoSelection(host: self, overlay: selectionOverlay)
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

    enum Mode {
        /// The pencil draws ink.
        case draw
        /// The pencil and fingers edit text boxes and images.
        case text
        /// The pencil (or a finger, with finger drawing on) draws a lasso
        /// selection; scrolling moves to fingers (or two fingers).
        case lasso
    }

    private(set) var mode: Mode = .draw

    /// Switches between drawing, text and lasso.
    ///
    /// Outside drawing, PencilKit's own taps (its Select All / Paste / Insert
    /// Space menu) are switched off; otherwise they show that menu and delay
    /// our own gestures. Scrolling, zooming and our gestures stay active.
    func setMode(_ newMode: Mode) {
        guard newMode != mode else {
            if mode == .lasso { applyLassoTouches() }
            return
        }

        // Leave the old mode.
        switch mode {
        case .text:
            elementLayer.isInteractive = false
            textTap.isEnabled = false
        case .lasso:
            if let savedPanTouchTypes { canvas.panGestureRecognizer.allowedTouchTypes = savedPanTouchTypes }
            canvas.panGestureRecognizer.minimumNumberOfTouches = savedPanMinimumTouches
            lasso.setEnabled(false, pencilOnly: canvas.drawingPolicy == .pencilOnly)
        case .draw:
            break
        }

        // Suspend PencilKit's gestures when leaving drawing, restore them when returning.
        if mode == .draw {
            let kept: [UIGestureRecognizer] = [
                canvas.panGestureRecognizer, canvas.drawingGestureRecognizer, textTap, seekTap, lasso.pan, lasso.tap,
            ] + [canvas.pinchGestureRecognizer].compactMap { $0 }
            suspendedRecognizers = Self.gestureRecognizers(in: canvas).filter { recognizer in
                recognizer.isEnabled && !kept.contains { $0 === recognizer }
            }
            suspendedRecognizers.forEach { $0.isEnabled = false }
        } else if newMode == .draw {
            suspendedRecognizers.forEach { $0.isEnabled = true }
            suspendedRecognizers = []
        }

        // Enter the new mode.
        mode = newMode
        switch newMode {
        case .text:
            elementLayer.isInteractive = true
            textTap.isEnabled = true
        case .lasso:
            savedPanTouchTypes = canvas.panGestureRecognizer.allowedTouchTypes
            savedPanMinimumTouches = canvas.panGestureRecognizer.minimumNumberOfTouches
            applyLassoTouches()
        case .draw:
            break
        }
        canvas.drawingGestureRecognizer.isEnabled = newMode == .draw
        updateSeekTap()
    }

    /// Re-applies lasso touch settings after "Draw with Finger" changes.
    func refreshLassoMode() {
        if mode == .lasso { applyLassoTouches() }
        updateSeekTap()
    }

    private func applyLassoTouches() {
        let pencilOnly = canvas.drawingPolicy == .pencilOnly
        canvas.panGestureRecognizer.allowedTouchTypes = pencilOnly
            ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            : (savedPanTouchTypes ?? canvas.panGestureRecognizer.allowedTouchTypes)
        canvas.panGestureRecognizer.minimumNumberOfTouches = pencilOnly ? 1 : 2
        lasso.setEnabled(true, pencilOnly: pencilOnly)
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
        // On rotation UIKit lays out inside its rotation animation. Animating the
        // page layers while PencilKit redraws at the new zoom makes the page
        // wobble, so everything is placed at its final position at once.
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            relayout()
            CATransaction.commit()
        }
    }

    private func relayout() {
        let newFitScale = bounds.width / PageLayout.pageWidth
        guard newFitScale > 0, abs(newFitScale - fitScale) > 0.0001 else {
            if canvas.frame != bounds { canvas.frame = bounds }
            updateZoomGeometry()
            return
        }
        // The point of the page in the middle of the screen, in canvas coordinates.
        let oldZoom = canvas.zoomScale
        let anchor = CGPoint(
            x: (canvas.contentOffset.x + canvas.bounds.width / 2) / max(oldZoom, 0.0001),
            y: (canvas.contentOffset.y + canvas.bounds.height / 2) / max(oldZoom, 0.0001)
        )
        let hadContent = fitScale != 0

        canvas.frame = bounds
        // Keep "fit to width" across rotation unless the user zoomed in.
        let wasFitted = !hadContent || abs(oldZoom - fitScale) < 0.0001
        fitScale = newFitScale
        canvas.minimumZoomScale = newFitScale
        canvas.maximumZoomScale = newFitScale * 5
        if wasFitted || canvas.zoomScale < newFitScale {
            canvas.zoomScale = newFitScale
        }
        updateZoomGeometry()
        if hadContent {
            keepVisible(anchor)
        }
        zoomDidEnd()
    }

    /// Scrolls so `point` (canvas coordinates) is in the middle of the screen,
    /// within the content.
    private func keepVisible(_ point: CGPoint) {
        let zoom = canvas.zoomScale
        let inset = canvas.adjustedContentInset
        let size = canvas.contentSize
        let visible = canvas.bounds.size
        let maxX = max(size.width + inset.right - visible.width, -inset.left)
        let maxY = max(size.height + inset.bottom - visible.height, -inset.top)
        let x = min(max(point.x * zoom - visible.width / 2, -inset.left), maxX)
        let y = min(max(point.y * zoom - visible.height / 2, -inset.top), maxY)
        canvas.setContentOffset(CGPoint(x: x, y: y), animated: false)
        updateScrollPosition()
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
        replay.syncGeometry()
        reportVisiblePage()
    }

    /// Call when a pinch ends: re-rasterize text for the new zoom.
    func zoomDidEnd() {
        let screenScale = window?.screen.scale ?? 2
        elementLayer.setRenderScale(min(screenScale * canvas.zoomScale, 6))
    }

    // MARK: Audio replay

    /// Fades ink written during `interval` after `now`; `nil` ends the replay.
    func setReplay(_ interval: DateInterval?, now: Date) {
        replay.show(interval, now: now)
        updateSeekTap()
    }

    /// Call after the ink changes.
    func inkDidChange() {
        if replay.isActive { replay.drawingDidChange() }
    }

    /// Tapping ink to hear it needs fingers free: not while they draw or edit text.
    private func updateSeekTap() {
        seekTap.isEnabled = replay.isActive && mode != .text && canvas.drawingPolicy == .pencilOnly
    }

    @objc private func handleSeekTap(_ gesture: UITapGestureRecognizer) {
        guard let date = replay.inkDate(near: gesture.location(in: elementLayer)) else { return }
        onInkTapped?(date)
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
