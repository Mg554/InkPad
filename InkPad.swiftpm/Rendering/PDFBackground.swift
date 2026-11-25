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
        case .passwordProtected: "This PDF is locked with a password. Open it with PDF Tools › Unlock PDF first."
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
    /// The file this PDF was opened from.
    var fileURL: URL { url }

    /// PDFKit's document, for outline, text and page tools.
    var pdfDocument: PDFDocument? { textDocument }

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
    func draw(page index: Int, in rect: CGRect, context: CGContext, dark: Bool = false) {
        if dark, let image = darkImage(page: index, size: rect.size), let cgImage = image.cgImage {
            context.saveGState()
            context.draw(cgImage, in: rect)
            context.restoreGState()
            return
        }
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
        }.filter { (rect: CGRect) -> Bool in
            !rect.isNull && rect.width > 1 && rect.height > 1
        }
        return PDFTextHit(text: text, lines: lines)
    }

    private static func rotation(of page: CGPDFPage) -> Int {
        let angle = Int(page.rotationAngle) % 360
        return angle < 0 ? angle + 360 : angle
    }
}

extension PDFBackground {
    /// Every line of text on a PDF page with its box in canvas coordinates,
    /// top to bottom (Ask This Page's paragraphs and citations).
    func lines(onPage index: Int, pageRect: CGRect) -> [(text: String, rect: CGRect)] {
        guard let page = textDocument?.page(at: index) else { return [] }
        let size = displaySize(ofPage: index)
        guard size.width > 0, pageRect.width > 0 else { return [] }
        let scale = pageRect.width / size.width
        let toDisplay = page.transform(for: .cropBox)
        func canvasPoint(_ point: CGPoint) -> CGPoint {
            let shown = point.applying(toDisplay)
            return CGPoint(x: pageRect.minX + shown.x * scale, y: pageRect.maxY - shown.y * scale)
        }
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        var result: [(text: String, rect: CGRect)] = []
        for line in selection.selectionsByLine() {
            let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bounds = line.bounds(for: page)
            let points = [
                canvasPoint(CGPoint(x: bounds.minX, y: bounds.minY)), canvasPoint(CGPoint(x: bounds.maxX, y: bounds.minY)),
                canvasPoint(CGPoint(x: bounds.minX, y: bounds.maxY)), canvasPoint(CGPoint(x: bounds.maxX, y: bounds.maxY)),
            ]
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { continue }
            result.append((text, CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)))
        }
        return result.sorted { $0.rect.minY < $1.rect.minY }
    }

    /// A night-reading copy: only neutral (low-saturation) pixels are
    /// inverted, so coloured diagrams and photos keep their original RGB.
    private static let darkCache = NSCache<NSString, UIImage>()

    private func darkImage(page index: Int, size: CGSize) -> UIImage? {
        let key = NSString(string: "\(index)-\(Int(size.width))x\(Int(size.height))")
        if let cached = Self.darkCache.object(forKey: key) { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let base = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            draw(page: index, in: CGRect(origin: .zero, size: size), context: renderer.cgContext)
        }
        guard let cg = base.cgImage,
              let provider = cg.dataProvider,
              let data = provider.data else { return nil }
        let bytes = cfDataBytes(data)
        let count = cg.width * cg.height * 4
        guard bytes.count >= count else { return nil }
        var pixels = Array(bytes[0..<count])
        for offset in stride(from: 0, to: count, by: 4) {
            let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
            if PDFNight.shouldInvert(r: r, g: g, b: b) {
                pixels[offset] = 255 - r
                pixels[offset + 1] = 255 - g
                pixels[offset + 2] = 255 - b
            }
        }
        guard let output = CGContext(data: &pixels, width: cg.width, height: cg.height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: cg.width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = output.makeImage() else { return nil }
        let result = UIImage(cgImage: image)
        Self.darkCache.setObject(result, forKey: key)
        return result
    }

    private func cfDataBytes(_ data: CFData) -> UnsafeBufferPointer<UInt8> {
        let length = CFDataGetLength(data)
        let pointer = CFDataGetBytePtr(data).map { UnsafeBufferPointer(start: $0, count: length) }
        return pointer ?? UnsafeBufferPointer(start: UnsafePointer<UInt8>(bitPattern: 1)!, count: 0)
    }

}

/// Pure pixel test for night PDF reading, kept separate so it can be unit-tested.
enum PDFNight {
    static func shouldInvert(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let saturation = Int(max(r, g, b)) - Int(min(r, g, b))
        return saturation < 28
    }
}
