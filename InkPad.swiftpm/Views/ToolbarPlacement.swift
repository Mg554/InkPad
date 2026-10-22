import SwiftUI

/// The edge of the page area the drawing toolbar is docked to. On the left
/// or right it stands upright, like Notability's movable toolbar.
enum ToolbarEdge: String, CaseIterable, Identifiable {
    case top, bottom, leading, trailing

    var id: Self { self }

    var isVertical: Bool { self == .leading || self == .trailing }

    var title: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .leading: "Left"
        case .trailing: "Right"
        }
    }

    var systemImage: String {
        switch self {
        case .top: "arrow.up.to.line"
        case .bottom: "arrow.down.to.line"
        case .leading: "arrow.left.to.line"
        case .trailing: "arrow.right.to.line"
        }
    }
}

/// Where along its edge the toolbar sits.
enum ToolbarAlignment: String {
    case start, center, end
}

/// The toolbar's docked position, chosen by dragging it.
struct ToolbarPlacement: Equatable {
    /// The editor area's coordinate space, which toolbar drags are measured in.
    static let coordinateSpace = "editorArea"

    var edge: ToolbarEdge
    var alignment: ToolbarAlignment

    /// The space kept between the toolbar and the edge.
    static let margin: CGFloat = 6

    /// Where a dragged toolbar docks: on the edge nearest the finger, and along
    /// that edge in the slot (start, middle or end) nearest where it was dropped.
    /// - Parameters:
    ///   - location: The finger, in `coordinateSpace`.
    ///   - toolbarFrame: The toolbar before the drag; `.zero` when unknown.
    static func drop(
        at location: CGPoint,
        translation: CGSize,
        toolbarFrame: CGRect,
        from current: ToolbarPlacement,
        in size: CGSize
    ) -> ToolbarPlacement {
        // A nudge leaves it where it is.
        guard hypot(translation.width, translation.height) > 24 else { return current }

        func distance(to edge: ToolbarEdge) -> CGFloat {
            let raw: CGFloat
            switch edge {
            case .top: raw = location.y
            case .bottom: raw = size.height - location.y
            case .leading: raw = location.x
            case .trailing: raw = size.width - location.x
            }
            // Moving to another edge takes a clear drag toward it.
            return edge == current.edge ? raw - 60 : raw
        }
        let edge = ToolbarEdge.allCases.min { distance(to: $0) < distance(to: $1) } ?? current.edge
        let length = edge.isVertical ? size.height : size.width

        guard edge == current.edge, toolbarFrame != .zero else {
            // On another edge the toolbar changes shape, so the finger decides.
            let along = (edge.isVertical ? location.y : location.x) / max(length, 1)
            return ToolbarPlacement(edge: edge, alignment: along < 1.0 / 3.0 ? .start : (along > 2.0 / 3.0 ? .end : .center))
        }
        let barLength = edge.isVertical ? toolbarFrame.height : toolbarFrame.width
        let dropped = edge.isVertical ? toolbarFrame.midY + translation.height : toolbarFrame.midX + translation.width
        let slots: [(ToolbarAlignment, CGFloat)] = [
            (.start, margin + barLength / 2),
            (.center, length / 2),
            (.end, length - margin - barLength / 2),
        ]
        let alignment = slots.min { abs($0.1 - dropped) < abs($1.1 - dropped) }?.0 ?? current.alignment
        return ToolbarPlacement(edge: edge, alignment: alignment)
    }

    /// Where the toolbar sits inside the editor area.
    var frameAlignment: Alignment {
        switch (edge, alignment) {
        case (.top, .start): return .topLeading
        case (.top, .center): return .top
        case (.top, .end): return .topTrailing
        case (.bottom, .start): return .bottomLeading
        case (.bottom, .center): return .bottom
        case (.bottom, .end): return .bottomTrailing
        case (.leading, .start): return .topLeading
        case (.leading, .center): return .leading
        case (.leading, .end): return .bottomLeading
        case (.trailing, .start): return .topTrailing
        case (.trailing, .center): return .trailing
        case (.trailing, .end): return .bottomTrailing
        }
    }
}

/// The outline shown where a dragged toolbar will dock.
struct ToolbarDropPreview: View {
    let placement: ToolbarPlacement

    var body: some View {
        let vertical = placement.edge.isVertical
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .frame(width: vertical ? 100 : 380, height: vertical ? 380 : 100)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.frameAlignment)
            .allowsHitTesting(false)
            .animation(.snappy(duration: 0.2), value: placement)
    }
}
