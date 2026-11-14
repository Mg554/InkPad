import Foundation
import PencilKit

/// How the open note's pages run: down the screen or across it, as picked
/// in Settings (Scrolling Direction). Ink and elements are always saved
/// with pages stacked vertically; the horizontal look is only on the open
/// canvas, so thumbnails, PDF export and moving pages between notes keep
/// working unchanged. A note picks the direction up when it opens.
enum ScrollAxis: String, CaseIterable, Identifiable {
    static let storageKey = "scrollAxis"

    case vertical, horizontal

    var id: Self { self }

    /// The name of the direction, in the app's language.
    var title: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }

    var symbol: String {
        switch self {
        case .vertical: "arrow.up.arrow.down"
        case .horizontal: "arrow.left.arrow.right"
        }
    }

    /// The direction the owner picked.
    static var current: ScrollAxis {
        ScrollAxis(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .vertical
    }

    var layoutAxis: PageLayout.Axis { self == .vertical ? .vertical : .horizontal }

    /// The stored content laid out for the open canvas, in display
    /// coordinates.
    func displayBackground(_ background: NoteBackground) -> NoteBackground {
        background.withAxis(layoutAxis)
    }

    /// Stored (vertically stacked) coordinates → the open canvas's display
    /// coordinates. A no-op in the vertical direction.
    static func toDisplay(drawing: PKDrawing, stored: NoteBackground, display: NoteBackground) -> PKDrawing {
        PageMapping.drawing(drawing, from: stored.layout, to: display.layout)
    }

    /// The open canvas's coordinates → stored. A no-op in the vertical
    /// direction.
    static func toStored(drawing: PKDrawing, stored: NoteBackground, display: NoteBackground) -> PKDrawing {
        PageMapping.drawing(drawing, from: display.layout, to: stored.layout)
    }

    /// Stored page elements → display coordinates.
    static func toDisplay(elements: [PageElement], stored: NoteBackground, display: NoteBackground) -> [PageElement] {
        map(elements, from: stored.layout, to: display.layout)
    }

    /// Display coordinates → stored page elements.
    static func toStored(elements: [PageElement], stored: NoteBackground, display: NoteBackground) -> [PageElement] {
        map(elements, from: display.layout, to: stored.layout)
    }

    /// Moves every element to the page it is on in the other layout.
    private static func map(_ elements: [PageElement], from source: PageLayout, to target: PageLayout) -> [PageElement] {
        guard source.axis != target.axis, source.pageRects.count == target.pageRects.count else { return elements }
        return elements.map { element in
            guard let move = PageMapping.move(for: CGPoint(x: element.frame.midX, y: element.frame.midY), from: source, to: target) else { return element }
            var moved = element
            moved.frame = element.frame.applying(move)
            return moved
        }
    }
}
