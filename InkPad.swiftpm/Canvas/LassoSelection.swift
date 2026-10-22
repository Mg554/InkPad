import PencilKit
import SwiftUI
import UIKit

/// Notability-style lasso: circle ink to select it, then use the menu
/// (Style, Duplicate, Cut, Copy, Paste, Delete) or drag the selection.
/// Replaces PencilKit's lasso, which cannot restyle strokes.
@MainActor
final class LassoSelection: NSObject, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
    enum DashStyle: String, CaseIterable, Identifiable {
        case solid, dashed, dotted
        var id: Self { self }
    }

    private weak var host: NoteCanvasHostView?
    /// Called after the drawing changes, to save and refresh undo state.
    var onChange: (() -> Void)?

    private let overlay: SelectionOverlayView
    private(set) lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private(set) lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var menu = UIEditMenuInteraction(delegate: self)

    /// Strokes in the selection (solid; dashes are applied when committing).
    private var selected: [PKStroke] = []
    /// Everything else in the drawing.
    private var others: [PKStroke] = []
    private var dash: DashStyle = .solid
    private var lassoPoints: [CGPoint] = []
    private var moveStart: CGPoint?
    private var drawingBeforeMove: PKDrawing?

    static let pasteboardType = "com.apple.drawing"

    init(host: NoteCanvasHostView, overlay: SelectionOverlayView) {
        self.host = host
        self.overlay = overlay
        super.init()
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        tap.delegate = self
        pan.isEnabled = false
        tap.isEnabled = false
        host.canvas.addGestureRecognizer(pan)
        host.canvas.addGestureRecognizer(tap)
        host.addInteraction(menu)
    }

    var hasSelection: Bool { !selected.isEmpty }

    func setEnabled(_ enabled: Bool, pencilOnly: Bool) {
        pan.isEnabled = enabled
        tap.isEnabled = enabled
        let pencil = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        let all = [UITouch.TouchType.direct, .pencil, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        pan.allowedTouchTypes = pencilOnly ? pencil : all
        if !enabled { clearSelection() }
    }

    // MARK: Gestures

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: overlay)
        switch gesture.state {
        case .began:
            menu.dismissMenu()
            if hasSelection, selectionBounds.insetBy(dx: -16, dy: -16).contains(point) {
                beginMove(at: point)
            } else {
                clearSelection()
                lassoPoints = [point]
                overlay.showLasso(lassoPoints)
            }
        case .changed:
            if let moveStart {
                overlay.moveSnapshot(by: CGPoint(x: point.x - moveStart.x, y: point.y - moveStart.y))
            } else {
                lassoPoints.append(point)
                overlay.showLasso(lassoPoints)
            }
        case .ended:
            if let moveStart {
                endMove(by: CGPoint(x: point.x - moveStart.x, y: point.y - moveStart.y))
            } else {
                finishLasso()
            }
        default:
            if moveStart != nil { endMove(by: .zero) }
            overlay.showLasso([])
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: overlay)
        if hasSelection, selectionBounds.contains(point) {
            presentMenu()
        } else {
            clearSelection()
            if UIPasteboard.general.contains(pasteboardTypes: [Self.pasteboardType]) {
                pastePoint = point
                presentMenu(at: point)
            }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }

    // MARK: Selecting

    private func finishLasso() {
        overlay.showLasso([])
        guard let host, lassoPoints.count > 4 else { return }
        let polygon = UIBezierPath()
        polygon.move(to: lassoPoints[0])
        lassoPoints.dropFirst().forEach { polygon.addLine(to: $0) }
        polygon.close()

        var inside: [PKStroke] = []
        var outside: [PKStroke] = []
        for stroke in host.canvas.drawing.strokes {
            let points = ShapeRecognizer.points(of: stroke)
            let hits = points.filter { polygon.contains($0) }.count
            if !points.isEmpty, Double(hits) / Double(points.count) >= 0.6 {
                inside.append(stroke)
            } else {
                outside.append(stroke)
            }
        }
        lassoPoints = []
        guard !inside.isEmpty else { return }
        selected = inside
        others = outside
        dash = .solid
        overlay.showSelection(selectionBounds)
        presentMenu()
    }

    func clearSelection() {
        selected = []
        others = []
        overlay.showSelection(nil)
        menu.dismissMenu()
    }

    private var selectionBounds: CGRect {
        selected.reduce(CGRect.null) { $0.union($1.renderBounds) }
    }

    // MARK: Moving

    private func beginMove(at point: CGPoint) {
        guard let host else { return }
        moveStart = point
        drawingBeforeMove = host.canvas.drawing
        // Show the selection as an image while dragging; the canvas keeps the rest.
        let bounds = selectionBounds
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = PKDrawing(strokes: selected).image(from: bounds, scale: (host.window?.screen.scale ?? 2) * host.canvas.zoomScale)
        }
        host.canvas.drawing = PKDrawing(strokes: others)
        overlay.beginSnapshot(image, frame: bounds)
    }

    private func endMove(by offset: CGPoint) {
        guard let before = drawingBeforeMove else { return }
        moveStart = nil
        drawingBeforeMove = nil
        overlay.endSnapshot()
        let move = CGAffineTransform(translationX: offset.x, y: offset.y)
        selected = selected.map { stroke in
            var moved = stroke
            moved.transform = stroke.transform.concatenating(move)
            return moved
        }
        commit(replacing: before)
        presentMenu()
    }

    // MARK: Editing

    /// Puts the selection back into the drawing, with one undo step back to `before`.
    private func commit(replacing before: PKDrawing) {
        guard let host else { return }
        host.canvas.drawing = PKDrawing(strokes: others + selected.flatMap { Self.dashed($0, style: dash) })
        host.canvas.undoManager?.registerUndo(withTarget: host.canvas) { [weak self] canvas in
            self?.clearSelection()
            canvas.drawing = before
        }
        overlay.showSelection(selectionBounds)
        onChange?()
    }

    private func edit(_ change: () -> Void) {
        guard let host else { return }
        let before = host.canvas.drawing
        change()
        commit(replacing: before)
    }

    var styleLevel: Int {
        let widths = selected.flatMap { $0.path.map(\.size.width) }.sorted()
        guard !widths.isEmpty else { return 5 }
        return WidthLevelBar.level(forWidth: widths[widths.count / 2], in: Self.widthRange)
    }

    var styleDash: DashStyle { dash }

    /// Widths offered for selected ink.
    static let widthRange: ClosedRange<CGFloat> = 1...30

    func setWidth(level: Int) {
        let target = WidthLevelBar.width(forLevel: level, in: Self.widthRange)
        edit {
            selected = selected.map { stroke in
                let widths = stroke.path.map(\.size.width).sorted()
                guard !widths.isEmpty, widths[widths.count / 2] > 0 else { return stroke }
                let factor = target / widths[widths.count / 2]
                let points = stroke.path.map { point in
                    PKStrokePoint(
                        location: point.location, timeOffset: point.timeOffset,
                        size: CGSize(width: point.size.width * factor, height: point.size.height * factor),
                        opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude
                    )
                }
                var resized = stroke
                resized.path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
                return resized
            }
        }
    }

    /// Recolors the selection; translucent ink (highlighter) keeps its transparency.
    func setColor(_ color: UIColor) {
        edit {
            selected = selected.map { stroke in
                var alpha: CGFloat = 1
                stroke.ink.color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
                var recolored = stroke
                recolored.ink = PKInk(stroke.ink.inkType, color: color.withAlphaComponent(alpha))
                return recolored
            }
        }
    }

    func setDash(_ style: DashStyle) {
        edit { dash = style }
    }

    // MARK: Menu

    private var pastePoint: CGPoint?

    private func presentMenu() {
        let bounds = selectionBounds
        presentMenu(at: CGPoint(x: bounds.midX, y: bounds.minY))
    }

    private func presentMenu(at point: CGPoint) {
        guard let host else { return }
        let location = overlay.convert(point, to: host)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var actions: [UIMenuElement] = []
        if hasSelection {
            actions += [
                UIAction(title: "Style", image: UIImage(systemName: "paintpalette")) { [weak self] _ in self?.showStylePanel() },
                UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplicateSelection() },
                UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.cutSelection() },
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copySelection() },
            ]
        }
        if UIPasteboard.general.contains(pasteboardTypes: [Self.pasteboardType]) {
            actions.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.pasteFromClipboard() })
        }
        if hasSelection {
            actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.deleteSelection() })
        }
        return actions.isEmpty ? nil : UIMenu(children: actions)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let host, hasSelection else { return .null }
        return overlay.convert(selectionBounds, to: host)
    }

    // Not named copy(), cut() or delete(): NSObject and UIResponder already
    // define methods with those names, which makes calls ambiguous.
    private func copySelection() {
        UIPasteboard.general.setData(PKDrawing(strokes: selected).dataRepresentation(), forPasteboardType: Self.pasteboardType)
    }

    private func cutSelection() {
        copySelection()
        deleteSelection()
    }

    private func deleteSelection() {
        edit { selected = [] }
        clearSelection()
    }

    private func duplicateSelection() {
        let copies = Self.offset(selected, by: CGPoint(x: 24, y: 24))
        edit {
            others += selected.flatMap { Self.dashed($0, style: dash) }
            selected = copies
        }
        presentMenu()
    }

    private func pasteFromClipboard() {
        guard let host,
              let data = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType),
              let pasted = try? PKDrawing(data: data), !pasted.strokes.isEmpty
        else { return }
        // Place the pasted ink where the menu was opened, or just offset from the original.
        let bounds = pasted.bounds
        let target = pastePoint ?? CGPoint(x: bounds.midX + 24, y: bounds.midY + 24)
        pastePoint = nil
        let strokes = Self.offset(pasted.strokes, by: CGPoint(x: target.x - bounds.midX, y: target.y - bounds.midY))
        if !hasSelection {
            others = host.canvas.drawing.strokes
        } else {
            others += selected.flatMap { Self.dashed($0, style: dash) }
        }
        dash = .solid
        edit { selected = strokes }
        presentMenu()
    }

    // MARK: Style panel

    private func showStylePanel() {
        guard let host, var presenter = Self.viewController(for: host) else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let panel = UIHostingController(rootView: SelectionStylePanel(selection: SelectionStyleModel(lasso: self)))
        panel.modalPresentationStyle = .popover
        panel.preferredContentSize = CGSize(width: 380, height: 420)
        if let popover = panel.popoverPresentationController {
            popover.sourceView = host
            popover.sourceRect = overlay.convert(selectionBounds, to: host)
            popover.permittedArrowDirections = [.up, .down]
        }
        presenter.present(panel, animated: true)
    }

    private static func viewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }

    // MARK: Helpers

    private static func offset(_ strokes: [PKStroke], by offset: CGPoint) -> [PKStroke] {
        let move = CGAffineTransform(translationX: offset.x, y: offset.y)
        return strokes.map { stroke in
            var moved = stroke
            moved.transform = stroke.transform.concatenating(move)
            return moved
        }
    }

    /// Splits a stroke into dashes or dots (PencilKit has no dashed ink).
    static func dashed(_ stroke: PKStroke, style: DashStyle) -> [PKStroke] {
        guard style != .solid else { return [stroke] }
        let points = Array(stroke.path.interpolatedPoints(by: .distance(1.5)))
        guard points.count > 2 else { return [stroke] }
        let widths = points.map(\.size.width).sorted()
        let width = max(widths[widths.count / 2], 1)
        let on = style == .dashed ? width * 3.5 : 0.01
        let off = style == .dashed ? width * 2.5 : width * 2
        var pieces: [PKStroke] = []
        var current: [PKStrokePoint] = []
        var travelled: CGFloat = 0
        var previous = points[0].location
        for point in points {
            travelled += hypot(point.location.x - previous.x, point.location.y - previous.y)
            previous = point.location
            let phase = travelled.truncatingRemainder(dividingBy: on + off)
            if phase <= on {
                current.append(point)
            } else if !current.isEmpty {
                pieces.append(piece(current, of: stroke))
                current = []
            }
        }
        if !current.isEmpty { pieces.append(piece(current, of: stroke)) }
        return pieces
    }

    private static func piece(_ points: [PKStrokePoint], of stroke: PKStroke) -> PKStroke {
        // A single point would not render; repeat it to draw a round dot.
        let controlPoints = points.count == 1 ? [points[0], points[0]] : points
        return PKStroke(
            ink: stroke.ink,
            path: PKStrokePath(controlPoints: controlPoints, creationDate: stroke.path.creationDate),
            transform: stroke.transform
        )
    }
}

/// Draws the lasso line, the selection box, and the dragged selection.
final class SelectionOverlayView: UIView {
    private let lassoLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let snapshotView = UIImageView()
    private var snapshotOrigin: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for shape in [lassoLayer, selectionLayer] {
            shape.fillColor = UIColor.systemBlue.withAlphaComponent(0.06).cgColor
            shape.strokeColor = UIColor.systemBlue.cgColor
            shape.lineWidth = 1.5
            shape.lineDashPattern = [6, 4]
            layer.addSublayer(shape)
        }
        lassoLayer.fillColor = UIColor.clear.cgColor
        addSubview(snapshotView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showLasso(_ points: [CGPoint]) {
        let path = UIBezierPath()
        if let first = points.first {
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
        lassoLayer.path = path.cgPath
    }

    func showSelection(_ rect: CGRect?) {
        selectionLayer.path = rect.map { UIBezierPath(roundedRect: $0.insetBy(dx: -8, dy: -8), cornerRadius: 10).cgPath }
    }

    func beginSnapshot(_ image: UIImage, frame: CGRect) {
        snapshotView.image = image
        snapshotView.frame = frame
        snapshotOrigin = frame.origin
        snapshotView.isHidden = false
    }

    func moveSnapshot(by offset: CGPoint) {
        snapshotView.frame.origin = CGPoint(x: snapshotOrigin.x + offset.x, y: snapshotOrigin.y + offset.y)
        // Move the selection box with it, without animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.setAffineTransform(CGAffineTransform(translationX: offset.x, y: offset.y))
        CATransaction.commit()
    }

    func endSnapshot() {
        snapshotView.isHidden = true
        snapshotView.image = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.setAffineTransform(.identity)
        CATransaction.commit()
    }
}

/// Live state for the Style panel.
@MainActor
final class SelectionStyleModel: ObservableObject {
    private weak var lasso: LassoSelection?
    @Published var level: Int { didSet { if level != oldValue { lasso?.setWidth(level: level) } } }
    @Published var dash: LassoSelection.DashStyle { didSet { if dash != oldValue { lasso?.setDash(dash) } } }

    init(lasso: LassoSelection) {
        self.lasso = lasso
        level = lasso.styleLevel
        dash = lasso.styleDash
    }

    func setColor(_ color: Color) {
        lasso?.setColor(UIColor(color))
    }
}
