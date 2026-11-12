import Foundation
import PDFKit
import PencilKit

/// Moves or copies pages from one note into another, keeping the ink as
/// editable strokes, text boxes and images as elements, PDF pages as PDF
/// pages and paper pages at their size.
enum PageTransfer {
    /// Where the pages go in the target note.
    enum Position: Hashable {
        case start
        case end
        /// After this page (zero-based).
        case after(Int)
    }

    /// One page lifted out of its note, in page coordinates (top at 0).
    struct LiftedPage {
        var source: PageSource
        var height: CGFloat
        var strokes: [PKStroke]
        var elements: [PageElement]
    }

    enum TransferError: LocalizedError {
        case noPages
        case cannotWritePDF

        var errorDescription: String? {
            switch self {
            case .noPages: tr("Choose at least one page.")
            case .cannotWritePDF: tr("The new PDF couldn't be written.")
            }
        }
    }

    /// The selected pages of a note, with what is on each.
    static func lift(_ indices: [Int], from content: NoteContent) -> [LiftedPage] {
        let background = content.makeBackground()
        let rects = background.layout.pageRects
        let gap: CGFloat = PageLayout.pageGap / 2
        var result: [LiftedPage] = []
        for index in indices.sorted() where rects.indices.contains(index) && background.pages.indices.contains(index) {
            let rect = rects[index]
            let range = (rect.minY - gap)...(rect.maxY + gap)
            let up = CGAffineTransform(translationX: 0, y: -rect.minY)
            var strokes: [PKStroke] = []
            for var stroke in content.drawing.strokes where range.contains(stroke.renderBounds.midY) {
                stroke.transform = stroke.transform.concatenating(up)
                strokes.append(stroke)
            }
            let elements: [PageElement] = (content.metadata.elements ?? [])
                .filter { range.contains($0.frame.midY) }
                .map { PageElement(id: UUID(), frame: $0.frame.offsetBy(dx: 0, dy: -rect.minY), content: $0.content) }
            result.append(LiftedPage(source: background.pages[index], height: rect.height, strokes: strokes, elements: elements))
        }
        return result
    }

    /// The target note with the pages put in; image files are copied into
    /// its folder. Returns the updated content to save.
    static func insert(
        _ lifted: [LiftedPage],
        from source: NoteContent,
        into target: NoteContent,
        at position: Position
    ) throws -> NoteContent {
        guard !lifted.isEmpty else { throw TransferError.noPages }
        let oldBackground = target.makeBackground()
        let oldRects = oldBackground.layout.pageRects
        var pages = target.metadata.resolvedPages(pdfPageCount: target.pdf?.pageCount ?? 0)
        let insertAt: Int
        switch position {
        case .start: insertAt = 0
        case .end: insertAt = pages.count
        case let .after(page): insertAt = min(max(page + 1, 0), pages.count)
        }

        // PDF pages: a new PDF with the target's pages, then the moved ones.
        var metadata = target.metadata
        var pdf = target.pdf
        var newSources: [PageSource] = []
        let movedPDFPages: [Int] = lifted.compactMap { page in
            if case let .pdf(index) = page.source { return index }
            return nil
        }
        if !movedPDFPages.isEmpty, let sourceDocument = source.pdf?.pdfDocument {
            let oldCount: Int = target.pdf?.pageCount ?? 0
            let combined: PDFDocument = target.pdf?.pdfDocument.map { PDFToolKit.document(with: Array(0..<oldCount), from: $0) } ?? PDFDocument()
            var next = oldCount
            for page in lifted {
                if case let .pdf(index) = page.source, let copy = sourceDocument.page(at: index)?.copy() as? PDFPage {
                    combined.insert(copy, at: combined.pageCount)
                    newSources.append(.pdf(next))
                    next += 1
                } else {
                    newSources.append(PageSource.paper(of: page.source.paperSize ?? PaperSize.standard))
                }
            }
            let fileName = "document-\(UUID().uuidString.prefix(8)).pdf"
            let url = target.directory.appendingPathComponent(fileName)
            guard combined.write(to: url) else { throw TransferError.cannotWritePDF }
            pdf = try PDFBackground(url: url)
            metadata.pdfFile = fileName
        } else {
            // Paper only (a PDF page without its PDF becomes plain paper).
            newSources = lifted.map { PageSource.paper(of: $0.source.paperSize ?? PaperSize.standard) }
        }

        pages.insert(contentsOf: newSources, at: insertAt)
        metadata.pages = pages
        metadata.pageCount = pages.filter(\.isPaper).count
        if let marks = metadata.bookmarks {
            metadata.bookmarks = marks.map { mark in
                var copy = mark
                if copy.page >= insertAt { copy.page += newSources.count }
                return copy
            }
        }
        let updated = NoteContent(metadata: metadata, drawing: target.drawing, pdf: pdf, directory: target.directory)
        let newRects = updated.makeBackground().layout.pageRects

        // Move what was written on later pages down.
        var strokes = target.drawing.strokes
        var elements = target.metadata.elements ?? []
        if insertAt < oldRects.count, insertAt + newSources.count < newRects.count {
            let shift: CGFloat = newRects[insertAt + newSources.count].minY - oldRects[insertAt].minY
            let boundary: CGFloat = oldRects[insertAt].minY - PageLayout.pageGap / 2
            let down = CGAffineTransform(translationX: 0, y: shift)
            for index in strokes.indices where strokes[index].renderBounds.midY > boundary {
                strokes[index].transform = strokes[index].transform.concatenating(down)
            }
            for index in elements.indices where elements[index].frame.midY > boundary {
                elements[index].frame = elements[index].frame.offsetBy(dx: 0, dy: shift)
            }
        }

        // Place the moved pages' ink and elements on their new pages.
        let fileManager = FileManager.default
        for (offset, page) in lifted.enumerated() {
            let newIndex = insertAt + offset
            guard newRects.indices.contains(newIndex) else { continue }
            let top = newRects[newIndex].minY
            let down = CGAffineTransform(translationX: 0, y: top)
            for var stroke in page.strokes {
                stroke.transform = stroke.transform.concatenating(down)
                strokes.append(stroke)
            }
            for var element in page.elements {
                element.frame = element.frame.offsetBy(dx: 0, dy: top)
                if case let .image(file) = element.content, isPlainFileName(file) {
                    let from = source.imageDirectory.appendingPathComponent(file)
                    let name = UUID().uuidString + "." + ((file as NSString).pathExtension.isEmpty ? "jpg" : (file as NSString).pathExtension)
                    try? fileManager.createDirectory(at: target.imageDirectory, withIntermediateDirectories: true)
                    if (try? fileManager.copyItem(at: from, to: target.imageDirectory.appendingPathComponent(name))) != nil {
                        element.content = .image(file: name)
                    } else {
                        continue
                    }
                }
                elements.append(element)
            }
        }
        metadata.elements = elements.isEmpty ? nil : elements
        return NoteContent(metadata: metadata, drawing: PKDrawing(strokes: strokes), pdf: pdf, directory: target.directory)
    }
}
