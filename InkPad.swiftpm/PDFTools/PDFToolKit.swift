import PDFKit
import UIKit
import Vision

/// A chapter (or section) of a PDF book, from its own outline.
struct BookChapter: Identifiable, Hashable {
    let id: String
    let title: String
    /// Zero-based first and last PDF page.
    let firstPage: Int
    let lastPage: Int
    /// 0 for chapters, 1 for their sections...
    let depth: Int

    var pageCount: Int { lastPage - firstPage + 1 }
    var pageLabel: String {
        firstPage == lastPage ? "p. \(firstPage + 1)" : "pp. \(firstPage + 1)–\(lastPage + 1)"
    }
}

enum PDFToolError: LocalizedError {
    case unreadable
    case locked
    case noPages
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .unreadable: "The PDF couldn't be read."
        case .locked: "The PDF is locked with a password. Use Unlock PDF in PDF Tools first."
        case .noPages: "Choose at least one page."
        case .cannotWrite: "The new PDF couldn't be written."
        }
    }
}

/// PDF work done on the iPad, offline: merging, splitting, taking pages
/// out, rotating, reading a book's chapters and their text. Everything
/// writes new files; originals are never changed.
enum PDFToolKit {
    // MARK: Opening

    static func open(_ url: URL) throws -> PDFDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { throw PDFToolError.unreadable }
        guard !document.isLocked else { throw PDFToolError.locked }
        guard document.pageCount > 0 else { throw PDFToolError.noPages }
        return document
    }

    /// A temporary file to write a result to, named after its title.
    static func temporaryURL(named title: String) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "PDF" : cleaned
        return folder.appendingPathComponent(name).appendingPathExtension("pdf")
    }

    // MARK: Pages

    /// A new document with these pages (zero-based), in this order.
    static func document(with pages: [Int], from source: PDFDocument) -> PDFDocument {
        let result = PDFDocument()
        for index in pages where index >= 0 && index < source.pageCount {
            guard let page = source.page(at: index)?.copy() as? PDFPage else { continue }
            result.insert(page, at: result.pageCount)
        }
        return result
    }

    static func write(_ document: PDFDocument, title: String) throws -> URL {
        guard document.pageCount > 0 else { throw PDFToolError.noPages }
        let url = temporaryURL(named: title)
        guard document.write(to: url) else { throw PDFToolError.cannotWrite }
        return url
    }

    /// Several documents one after another.
    static func merge(_ documents: [PDFDocument]) -> PDFDocument {
        let result = PDFDocument()
        for document in documents {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
                result.insert(page, at: result.pageCount)
            }
        }
        return result
    }

    /// The document with these pages turned by `degrees` (90, 180, 270).
    static func rotating(_ pages: Set<Int>, by degrees: Int, in source: PDFDocument) -> PDFDocument {
        let result = document(with: Array(0..<source.pageCount), from: source)
        for index in pages where index < result.pageCount {
            guard let page = result.page(at: index) else { continue }
            page.rotation = (page.rotation + degrees) % 360
        }
        return result
    }

    /// Every page except these.
    static func removing(_ pages: Set<Int>, from source: PDFDocument) -> PDFDocument {
        let kept = (0..<source.pageCount).filter { !pages.contains($0) }
        return document(with: kept, from: source)
    }

    /// Reads "1-5, 9, 12-14" (one-based) as zero-based page numbers.
    static func pages(from text: String, pageCount: Int) -> [Int] {
        var result: [Int] = []
        let parts = text.replacingOccurrences(of: "–", with: "-").split(separator: ",")
        for part in parts {
            let bounds = part.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let first = bounds.first.flatMap({ Int($0) }) else { continue }
            let last = bounds.count > 1 ? (Int(bounds[1]) ?? first) : first
            let low = max(min(first, last), 1)
            let high = min(max(first, last), pageCount)
            guard low <= high else { continue }
            for page in low...high { result.append(page - 1) }
        }
        var seen: Set<Int> = []
        return result.filter { seen.insert($0).inserted }
    }

    // MARK: Splitting

    struct Part {
        let title: String
        let pages: [Int]
    }

    /// Parts of `size` pages each.
    static func parts(every size: Int, pageCount: Int, title: String) -> [Part] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: pageCount, by: size).map { start in
            let end = min(start + size, pageCount)
            return Part(title: "\(title) (pp. \(start + 1)–\(end))", pages: Array(start..<end))
        }
    }

    /// One part per top-level chapter of the book's outline.
    static func parts(byChapters chapters: [BookChapter]) -> [Part] {
        chapters.filter { $0.depth == 0 }.map { chapter in
            Part(title: chapter.title, pages: Array(chapter.firstPage...chapter.lastPage))
        }
    }

    // MARK: Chapters

    /// The book's chapters and sections from its outline (bookmarks), with
    /// the pages each one covers. Empty when the PDF has no outline.
    static func chapters(of document: PDFDocument, maxDepth: Int = 2) -> [BookChapter] {
        guard let root = document.outlineRoot else { return [] }
        var flat: [(title: String, page: Int, depth: Int)] = []
        func visit(_ item: PDFOutline, depth: Int) {
            for index in 0..<item.numberOfChildren {
                guard let child = item.child(at: index) else { continue }
                if let page = child.destination?.page {
                    let pageIndex = document.index(for: page)
                    let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if pageIndex >= 0, pageIndex < document.pageCount, !title.isEmpty {
                        flat.append((title, pageIndex, depth))
                    }
                }
                if depth + 1 <= maxDepth { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        var chapters: [BookChapter] = []
        for (offset, item) in flat.enumerated() {
            // A chapter ends where the next item at its depth (or above) starts.
            var end = document.pageCount - 1
            for next in flat[(offset + 1)...] where next.depth <= item.depth {
                end = max(next.page - 1, item.page)
                break
            }
            chapters.append(BookChapter(id: "\(offset)-\(item.page)", title: item.title, firstPage: item.page, lastPage: end, depth: item.depth))
        }
        return chapters
    }

    /// The sections directly inside a chapter.
    static func sections(of chapter: BookChapter, in chapters: [BookChapter]) -> [BookChapter] {
        chapters.filter { item in
            item.depth == chapter.depth + 1 && item.firstPage >= chapter.firstPage && item.firstPage <= chapter.lastPage
        }
    }

    // MARK: Text

    /// The text of these pages. Scanned pages without text are read with
    /// Vision on the iPad (English and Arabic).
    static func text(of pages: ClosedRange<Int>, in document: PDFDocument, limit: Int = 60_000) -> String {
        var parts: [String] = []
        var total = 0
        for index in pages where index >= 0 && index < document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var pageText = page.string ?? ""
            if pageText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                pageText = recognize(page)
            }
            parts.append(pageText)
            total += pageText.count
            if total > limit { break }
        }
        return parts.joined(separator: "\n")
    }

    /// Reads a page that has no text layer (a scan).
    static func recognize(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .cropBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .cropBox)
        guard let cgImage = image.cgImage else { return "" }
        return NoteReader.recognizeText(in: cgImage)
    }

    /// Which PDF page a layout page shows, for a note made of a PDF and paper.
    static func layoutIndex(ofPDFPage pdfPage: Int, in pages: [PageSource]) -> Int? {
        pages.firstIndex(of: .pdf(pdfPage))
    }
}
