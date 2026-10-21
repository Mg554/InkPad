import CoreGraphics

/// Page geometry in canvas points. Every page is `pageWidth` wide and pages
/// are stacked vertically; the canvas is zoomed so a page fits the screen width.
struct PageLayout: Equatable {
    static let pageWidth: CGFloat = 768
    /// Template paper is A4-proportioned.
    static let templatePageSize = CGSize(width: pageWidth, height: 1086)
    static let pageGap: CGFloat = 24

    let pageRects: [CGRect]
    let contentSize: CGSize

    init(pageSizes: [CGSize]) {
        var rects: [CGRect] = []
        var y: CGFloat = 0
        for size in pageSizes {
            rects.append(CGRect(origin: CGPoint(x: 0, y: y), size: size))
            y += size.height + Self.pageGap
        }
        pageRects = rects
        contentSize = CGSize(
            width: Self.pageWidth,
            height: max(y - Self.pageGap, Self.templatePageSize.height)
        )
    }
}
