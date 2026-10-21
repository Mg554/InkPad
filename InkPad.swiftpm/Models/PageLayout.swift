import CoreGraphics

/// Page geometry in canvas points. Pages are A4-proportioned and stacked
/// vertically; the canvas is zoomed so a page fits the screen width.
enum PageLayout {
    static let pageSize = CGSize(width: 768, height: 1086)
    static let pageGap: CGFloat = 24

    static func pageRect(at index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * (pageSize.height + pageGap),
            width: pageSize.width,
            height: pageSize.height
        )
    }

    static func contentSize(pageCount: Int) -> CGSize {
        let count = CGFloat(max(pageCount, 1))
        return CGSize(
            width: pageSize.width,
            height: count * pageSize.height + (count - 1) * pageGap
        )
    }
}
