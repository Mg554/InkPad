import CoreGraphics

/// Page geometry in canvas points. Every page is `pageWidth` wide; pages
/// run down the screen or across it, as the owner picked in Settings. The
/// canvas is zoomed so a page fits the screen width either way.
struct PageLayout: Equatable {
    static let pageWidth: CGFloat = 768
    /// Template paper is A4-proportioned.
    static let templatePageSize = CGSize(width: pageWidth, height: 1086)
    static let pageGap: CGFloat = 24

    /// Which way the pages run. Ink is always stored with pages stacked
    /// vertically (`vertical`); horizontal is only how the open note shows
    /// it (see `ScrollAxis`).
    enum Axis: Equatable {
        case vertical, horizontal

        /// The coordinate along which pages advance.
        func step(_ size: CGSize) -> CGFloat { self == .vertical ? size.height : size.width }

        /// Axis-aware rect reading, so page math reads the same for both
        /// directions: where a page starts and ends along the pages'
        /// direction, how long it is, and where its middle is.
        func minCorner(of rect: CGRect) -> CGFloat { self == .vertical ? rect.minY : rect.minX }
        func maxCorner(of rect: CGRect) -> CGFloat { self == .vertical ? rect.maxY : rect.maxX }
        func length(of rect: CGRect) -> CGFloat { self == .vertical ? rect.height : rect.width }
        func mid(of rect: CGRect) -> CGFloat { self == .vertical ? rect.midY : rect.midX }
        func contains(_ value: CGFloat, in rect: CGRect) -> Bool { minCorner(of: rect) <= value && value <= maxCorner(of: rect) }
    }

    let axis: Axis
    let pageRects: [CGRect]
    let contentSize: CGSize

    init(pageSizes: [CGSize], axis: Axis = .vertical) {
        self.axis = axis
        var rects: [CGRect] = []
        var advanced: CGFloat = 0
        for size in pageSizes {
            let origin = axis == .vertical ? CGPoint(x: 0, y: advanced) : CGPoint(x: advanced, y: 0)
            rects.append(CGRect(origin: origin, size: size))
            advanced += axis.step(size) + Self.pageGap
        }
        let reached = max(advanced - Self.pageGap, axis == .vertical ? Self.templatePageSize.height : Self.templatePageSize.width)
        let cross = pageSizes.map(\.height).max().map { max($0, Self.templatePageSize.height) } ?? Self.templatePageSize.height
        contentSize = axis == .vertical
            ? CGSize(width: Self.pageWidth, height: reached)
            : CGSize(width: reached, height: cross)
        pageRects = rects
    }
}
