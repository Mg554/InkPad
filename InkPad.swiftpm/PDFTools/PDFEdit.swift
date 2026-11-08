import CoreText
import PDFKit
import UIKit
import WebKit

/// Convert and Protect tools, on the iPad: images ↔ PDF, compress,
/// password, redact, watermark, page numbers and signatures. Each writes a
/// new file; originals never change.
enum PDFEdit {
    // MARK: Page drawing

    /// The size a page is shown at (rotation applied), in points.
    static func shownSize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .cropBox)
        let turned = page.rotation % 180 != 0
        return CGSize(width: turned ? bounds.height : bounds.width, height: turned ? bounds.width : bounds.height)
    }

    /// Writes every page as it is (vector) with `overlay` drawn on top, in
    /// the shown page's coordinates (y up, origin bottom-left).
    static func rewrite(_ document: PDFDocument, to url: URL, overlay: (Int, CGContext, CGSize) -> Void) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { throw PDFToolError.cannotWrite }
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                let size = shownSize(of: page)
                var box = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &box)
                context.saveGState()
                context.concatenate(page.transform(for: .cropBox))
                page.draw(with: .cropBox, to: context)
                context.restoreGState()
                context.saveGState()
                overlay(index, context, size)
                context.restoreGState()
                context.endPage()
            }
        }
        context.closePDF()
    }

    /// Pages as pictures (JPEG), which removes hidden text and objects under
    /// redactions and makes big scans smaller. `pages` nil means every page;
    /// other pages are copied as they are.
    static func rasterize(
        _ document: PDFDocument,
        to url: URL,
        pages: Set<Int>? = nil,
        resolution: CGFloat = 2,
        quality: CGFloat = 0.7,
        keepsText: Bool = false,
        marks: ((Int, CGContext, CGSize) -> Void)? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { throw PDFToolError.cannotWrite }
        let total = document.pageCount
        for index in 0..<total {
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                let size = shownSize(of: page)
                var box = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &box)
                if pages?.contains(index) ?? true {
                    let pixels = CGSize(width: size.width * resolution, height: size.height * resolution)
                    let picture = page.thumbnail(of: pixels, for: .cropBox)
                    if let data = picture.jpegData(compressionQuality: quality),
                       let provider = CGDataProvider(data: data as CFData),
                       let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                        context.draw(image, in: box)
                        if keepsText, let cg = picture.cgImage {
                            BookOCR.drawInvisible(BookOCR.lines(in: cg), pageSize: size, in: context)
                        }
                    }
                } else {
                    context.saveGState()
                    context.concatenate(page.transform(for: .cropBox))
                    page.draw(with: .cropBox, to: context)
                    context.restoreGState()
                }
                if let marks {
                    context.saveGState()
                    marks(index, context, size)
                    context.restoreGState()
                }
                context.endPage()
            }
            progress?(index + 1, total)
        }
        context.closePDF()
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Images

    /// One page per picture, about A4 on its long side.
    static func pdf(from images: [UIImage], to url: URL) throws {
        guard !images.isEmpty, let context = CGContext(url as CFURL, mediaBox: nil, nil) else { throw PDFToolError.noPages }
        for image in images {
            guard let cg = image.normalized().cgImage else { continue }
            let long: CGFloat = 842
            let width = CGFloat(cg.width)
            let height = CGFloat(cg.height)
            let factor: CGFloat = long / max(width, height)
            var box = CGRect(x: 0, y: 0, width: width * factor, height: height * factor)
            context.beginPage(mediaBox: &box)
            context.draw(cg, in: box)
            context.endPage()
        }
        context.closePDF()
    }

    /// Pages as JPEG pictures in a temporary folder.
    static func pageImages(_ document: PDFDocument, pages: [Int], title: String, resolution: CGFloat = 2.5) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in pages {
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                let size = shownSize(of: page)
                let picture = page.thumbnail(of: CGSize(width: size.width * resolution, height: size.height * resolution), for: .cropBox)
                let url = folder.appendingPathComponent("\(title) p\(index + 1).jpg")
                if let data = picture.jpegData(compressionQuality: 0.9), (try? data.write(to: url)) != nil {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// The pictures stored inside a PDF (JPEG ones as they are, others as PNG).
    static func extractImages(_ document: PDFDocument, title: String) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        var count = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.pageRef, let dictionary = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            var objects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects
            else { continue }
            var found: [CGPDFStreamRef] = []
            CGPDFDictionaryApplyBlock(objects, { _, object, _ in
                var stream: CGPDFStreamRef?
                if CGPDFObjectGetValue(object, .stream, &stream), let stream { found.append(stream) }
                return true
            }, nil)
            for stream in found {
                guard let streamDictionary = CGPDFStreamGetDictionary(stream) else { continue }
                var subtype: UnsafePointer<Int8>?
                guard CGPDFDictionaryGetName(streamDictionary, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" else { continue }
                var format = CGPDFDataFormat.raw
                guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { continue }
                count += 1
                let base = folder.appendingPathComponent("\(title) image \(count)")
                if format == .jpegEncoded {
                    let url = base.appendingPathExtension("jpg")
                    if (try? data.write(to: url)) != nil { urls.append(url) }
                } else if format == .JPEG2000 {
                    let url = base.appendingPathExtension("jp2")
                    if (try? data.write(to: url)) != nil { urls.append(url) }
                } else if let image = rawImage(data, dictionary: streamDictionary), let png = image.pngData() {
                    let url = base.appendingPathExtension("png")
                    if (try? png.write(to: url)) != nil { urls.append(url) }
                }
            }
        }
        return urls
    }

    /// An uncompressed PDF image (8-bit gray or RGB).
    private static func rawImage(_ data: Data, dictionary: CGPDFDictionaryRef) -> UIImage? {
        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        var bits: CGPDFInteger = 8
        guard CGPDFDictionaryGetInteger(dictionary, "Width", &width), CGPDFDictionaryGetInteger(dictionary, "Height", &height) else { return nil }
        _ = CGPDFDictionaryGetInteger(dictionary, "BitsPerComponent", &bits)
        guard bits == 8, width > 0, height > 0 else { return nil }
        let pixels = Int(width) * Int(height)
        let components = data.count / max(pixels, 1)
        guard components == 1 || components == 3 else { return nil }
        let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 8 * components,
                                  bytesPerRow: Int(width) * components, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: Text on pages

    /// Draws one line of text centered at `center` (y up), turned by `degrees`.
    static func drawText(_ text: String, size: CGFloat, color: UIColor, at center: CGPoint, degrees: CGFloat = 0, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color.cgColor])
        let line = CTLineCreateWithAttributedString(attributed)
        let width: CGFloat = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: degrees * CGFloat.pi / 180)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -width / 2, y: -size / 3)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    enum NumberPlace: String, CaseIterable, Identifiable {
        case bottomCenter, bottomRight, bottomLeft, topRight
        var id: Self { self }
        var title: String {
            switch self {
            case .bottomCenter: "Bottom Center"
            case .bottomRight: "Bottom Right"
            case .bottomLeft: "Bottom Left"
            case .topRight: "Top Right"
            }
        }

        func point(in size: CGSize) -> CGPoint {
            let margin: CGFloat = 28
            switch self {
            case .bottomCenter: return CGPoint(x: size.width / 2, y: margin)
            case .bottomRight: return CGPoint(x: size.width - margin * 1.6, y: margin)
            case .bottomLeft: return CGPoint(x: margin * 1.6, y: margin)
            case .topRight: return CGPoint(x: size.width - margin * 1.6, y: size.height - margin)
            }
        }
    }

    // MARK: Password

    static func protect(_ document: PDFDocument, password: String, to url: URL) throws {
        let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        guard document.write(to: url, withOptions: options) else { throw PDFToolError.cannotWrite }
    }

    /// Opens a locked PDF with its password, as an unlocked copy.
    static func unlocked(_ url: URL, password: String) throws -> PDFDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { throw PDFToolError.unreadable }
        if document.isLocked {
            guard document.unlock(withPassword: password) else { throw UnlockError.wrongPassword }
        }
        // A fresh document without the lock.
        return PDFToolKit.document(with: Array(0..<document.pageCount), from: document)
    }

    enum UnlockError: LocalizedError {
        case wrongPassword
        var errorDescription: String? { "That password doesn't open this PDF." }
    }

    // MARK: Redaction

    /// Where these words appear on each page (page space, for the page's own transform).
    static func places(of words: [String], in document: PDFDocument) -> [Int: [CGRect]] {
        var result: [Int: [CGRect]] = [:]
        for word in words where word.trimmingCharacters(in: .whitespaces).count >= 2 {
            for selection in document.findString(word, withOptions: [.caseInsensitive]) {
                for page in selection.pages {
                    let index = document.index(for: page)
                    let rect = selection.bounds(for: page).insetBy(dx: -1.5, dy: -1.5)
                    result[index, default: []].append(rect)
                }
            }
        }
        return result
    }

    // MARK: Web pages

    /// A web page as an A4 PDF, paginated like printing.
    @MainActor
    static func webPage(_ address: URL, to url: URL) async throws {
        let loader = WebPageLoader()
        let webView = try await loader.load(address)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 36, dy: 36)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        guard renderer.numberOfPages > 0, data.write(to: url, atomically: true) else { throw PDFToolError.cannotWrite }
    }
}

/// Loads a web page off screen and waits for it to finish.
@MainActor
private final class WebPageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<WKWebView, Error>?
    private let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))

    func load(_ url: URL) async throws -> WKWebView {
        webView.navigationDelegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give late images a moment.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            continuation?.resume(returning: webView)
            continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension UIImage {
    /// The picture redrawn upright (camera photos carry a rotation flag).
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
