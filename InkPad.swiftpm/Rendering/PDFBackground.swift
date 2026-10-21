import CoreGraphics
import Foundation

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

/// A read-only PDF shown underneath the ink. Owns PDF page geometry and drawing.
final class PDFBackground {
    private let document: CGPDFDocument
    let pageCount: Int

    init(url: URL) throws {
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

    private static func rotation(of page: CGPDFPage) -> Int {
        let angle = Int(page.rotationAngle) % 360
        return angle < 0 ? angle + 360 : angle
    }
}
