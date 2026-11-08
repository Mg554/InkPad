import CoreText
import PDFKit
import UIKit
import Vision

/// A line of text read from an image, with where it is (0...1, y down).
struct OCRLine: Sendable {
    let text: String
    let box: CGRect
}

/// Reads scanned pages on the iPad (Vision, English and Arabic) and gives
/// PDFs an invisible text layer, so scans can be searched, selected,
/// highlighted and read by Living Notes and AI.
enum BookOCR {
    // MARK: Reading

    /// The languages to read: English and Arabic where this iPad supports them.
    static func languages(for request: VNRecognizeTextRequest) -> [String] {
        let wanted = ["en-US", "ar-SA", "ar"]
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let picked = wanted.filter { supported.contains($0) }
        return picked.isEmpty ? ["en-US"] : picked
    }

    /// Lines of text in an image, top to bottom.
    static func lines(in image: CGImage) -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages(for: request)
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations.compactMap { observation -> OCRLine? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            let box = observation.boundingBox
            // Vision's origin is bottom-left; ours is top-left.
            let flipped = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            return OCRLine(text: text, box: flipped)
        }
        .sorted { (a: OCRLine, b: OCRLine) -> Bool in
            if abs(a.box.midY - b.box.midY) > min(a.box.height, b.box.height) * 0.5 { return a.box.midY < b.box.midY }
            return a.box.minX < b.box.minX
        }
    }

    /// Plain text from lines, one line each.
    static func text(of lines: [OCRLine]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// Lines arranged as a Markdown table: rows by height, cells by the
    /// columns the lines line up in. `nil` when it doesn't look like a table.
    static func table(from lines: [OCRLine]) -> String? {
        guard lines.count >= 4 else { return nil }
        // Rows: lines whose middles are close vertically.
        var rows: [[OCRLine]] = []
        for line in lines.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last?.last, abs(last.box.midY - line.box.midY) < last.box.height * 0.6 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        let wide = rows.filter { $0.count >= 2 }
        guard wide.count >= 2 else { return nil }
        // Columns: the left edges that come back row after row.
        var starts: [CGFloat] = []
        for row in rows {
            for cell in row {
                if !starts.contains(where: { abs($0 - cell.box.minX) < 0.04 }) { starts.append(cell.box.minX) }
            }
        }
        starts.sort()
        guard starts.count >= 2, starts.count <= 12 else { return nil }
        func column(of cell: OCRLine) -> Int {
            var best = 0
            var distance = CGFloat.greatestFiniteMagnitude
            for (index, start) in starts.enumerated() {
                let gap = abs(start - cell.box.minX)
                if gap < distance {
                    distance = gap
                    best = index
                }
            }
            return best
        }
        var markdown: [String] = []
        for (offset, row) in rows.enumerated() {
            var cells = Array(repeating: "", count: starts.count)
            for cell in row.sorted(by: { $0.box.minX < $1.box.minX }) {
                let index = column(of: cell)
                cells[index] = cells[index].isEmpty ? cell.text : cells[index] + " " + cell.text
            }
            let clean = cells.map { $0.replacingOccurrences(of: "|", with: "/") }
            markdown.append("| " + clean.joined(separator: " | ") + " |")
            if offset == 0 {
                markdown.append("|" + Array(repeating: " --- |", count: starts.count).joined())
            }
        }
        return markdown.joined(separator: "\n")
    }

    // MARK: Pages

    /// True when a page has (almost) no text of its own: a scan.
    static func needsReading(_ page: PDFPage) -> Bool {
        let text = page.string ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20
    }

    /// The page as an image, as it is shown (rotation applied).
    static func image(of page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        let bounds = page.bounds(for: .cropBox)
        let turned = page.rotation % 180 != 0
        let width: CGFloat = turned ? bounds.height : bounds.width
        let height: CGFloat = turned ? bounds.width : bounds.height
        let size = CGSize(width: width * scale, height: height * scale)
        return page.thumbnail(of: size, for: .cropBox).cgImage
    }

    // MARK: Text layer

    struct Progress: Sendable {
        var done: Int
        var total: Int
        var read: Int
    }

    /// A copy of the document whose scanned pages carry an invisible text
    /// layer. Pages that already have text are copied as they are. Page
    /// count, order and sizes stay the same, so ink on a note still lines up.
    static func searchable(
        _ document: PDFDocument,
        onlyScans: Bool = true,
        to url: URL,
        progress: @escaping @Sendable (Progress) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Int {
        let total = document.pageCount
        guard total > 0 else { throw PDFToolError.noPages }
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { throw PDFToolError.cannotWrite }
        var read = 0
        for index in 0..<total {
            if isCancelled() { break }
            autoreleasepool {
                guard let page = document.page(at: index) else { return }
                let bounds = page.bounds(for: .cropBox)
                let turned = page.rotation % 180 != 0
                let size = CGSize(width: turned ? bounds.height : bounds.width, height: turned ? bounds.width : bounds.height)
                var box = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &box)
                // The page itself, vector, as shown.
                context.saveGState()
                context.concatenate(page.transform(for: .cropBox))
                page.draw(with: .cropBox, to: context)
                context.restoreGState()
                if !onlyScans || needsReading(page), let image = image(of: page) {
                    let lines = lines(in: image)
                    drawInvisible(lines, pageSize: size, in: context)
                    if !lines.isEmpty { read += 1 }
                }
                context.endPage()
            }
            progress(Progress(done: index + 1, total: total, read: read))
        }
        context.closePDF()
        if isCancelled() {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        return read
    }

    /// Writes each line as invisible text over where it appears (PDF
    /// coordinates, y up), stretched to the line's width.
    private static func drawInvisible(_ lines: [OCRLine], pageSize: CGSize, in context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for line in lines {
            let rect = CGRect(
                x: line.box.minX * pageSize.width,
                y: (1 - line.box.maxY) * pageSize.height,
                width: line.box.width * pageSize.width,
                height: line.box.height * pageSize.height
            )
            guard rect.width > 1, rect.height > 1 else { continue }
            let fontSize: CGFloat = max(rect.height * 0.85, 1)
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attributed = NSAttributedString(string: line.text, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let width: CGFloat = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            guard width > 0 else { continue }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.15)
            context.scaleBy(x: rect.width / width, y: 1)
            context.textPosition = .zero
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// How many pages of the document look like scans.
    static func scanCount(in document: PDFDocument) -> Int {
        var count = 0
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), needsReading(page) { count += 1 }
        }
        return count
    }
}
