import CoreGraphics
import Foundation
import PDFKit

enum PDFOpenError: LocalizedError {
    case unreadable
    case passwordProtected
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file is not a readable PDF."
        case .passwordProtected: "Password-protected PDFs are not supported yet."
        case .empty: "The PDF has no pages."
        }
    }
}

/// Text of a PDF found under a lasso.
struct PDFTextHit {
    var text: String
    /// Each line's box, in canvas coordinates.
    var lines: [CGRect]
}

/// A read-only PDF shown underneath the ink. Owns PDF page geometry and drawing.
final class PDFBackground {
    private let document: CGPDFDocument
    private let url: URL
    /// PDFKit's copy, opened when text is first needed.
    private lazy var textDocument: PDFDocument? = PDFDocument(url: url)
    let pageCount: Int

    init(url: URL) throws {
        self.url = url
        guard let document = CGPDFDocument(url as CFURL) else { throw PDFOpenError.unreadable }
        guard document.isUnlocked else { throw PDFOpenError.passwordProtected }
        guard document.numberOfPages > 0 else { throw PDFOpenError.empty }
        self.document = document
        self.pageCount = document.numberOfPages
    }

    /// Page size as displayed (crop box with the page's rotation), in PDF points.
    func displaySize(ofPage index: Int) -> CGSize {
        guard let page = document.page(at: index + 1) else { return PageLayout.templatePageSize }
        let box = page.getBoxRect(.cropBox)
        return Self.rotation(of: page).isMultiple(of: 180)
            ? box.size
            : CGSize(width: box.height, height: box.width)
    }

    /// Draws the page scaled to fill `rect` (UIKit, y-down coordinates).
    func draw(page index: Int, in rect: CGRect, context: CGContext) {
        guard let page = document.page(at: index + 1) else { return }
        let box = page.getBoxRect(.cropBox)
        let size = displaySize(ofPage: index)
        guard size.width > 0, size.height > 0 else { return }
        let scale = rect.width / size.width

        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high

        // Flip to PDF's y-up space with the origin at the page's bottom-left.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: scale, y: -scale)
        // Apply /Rotate (clockwise when displayed).
        switch Self.rotation(of: page) {
        case 90:
            context.translateBy(x: 0, y: box.width)
            context.rotate(by: -.pi / 2)
        case 180:
            context.translateBy(x: box.width, y: box.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: box.height, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(page)
    }

    /// The text of page `index` inside `rect`. Both rects are in canvas
    /// coordinates; `pageRect` is where the page is drawn.
    func text(onPage index: Int, in rect: CGRect, pageRect: CGRect) -> PDFTextHit? {
        guard let page = textDocument?.page(at: index) else { return nil }
        let size = displaySize(ofPage: index)
        guard size.width > 0, pageRect.width > 0 else { return nil }
        let scale = pageRect.width / size.width
        // Page space to the displayed (rotated, cropped) page, y up.
        let toDisplay = page.transform(for: .cropBox)
        let toPage = toDisplay.inverted()
        func pagePoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - pageRect.minX) / scale, y: (pageRect.maxY - point.y) / scale).applying(toPage)
        }
        func canvasPoint(_ point: CGPoint) -> CGPoint {
            let shown = point.applying(toDisplay)
            return CGPoint(x: pageRect.minX + shown.x * scale, y: pageRect.maxY - shown.y * scale)
        }
        func box(_ points: [CGPoint]) -> CGRect {
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        func corners(_ rect: CGRect) -> [CGPoint] {
            [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
             CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        }

        let area = box(corners(rect).map(pagePoint))
        guard let selection = page.selection(for: area),
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        let lines = selection.selectionsByLine().map { line in
            box(corners(line.bounds(for: page)).map(canvasPoint))
        }.filter { !$0.isNull && $0.width > 1 && $0.height > 1 }
        return PDFTextHit(text: text, lines: lines)
    }

    private static func rotation(of page: CGPDFPage) -> Int {
        let angle = Int(page.rotationAngle) % 360
        return angle < 0 ? angle + 360 : angle
    }
}
