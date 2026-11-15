import UIKit
import Vision

/// A paragraph on a page, with where it is, so an answer can cite it and
/// the citation can light it up.
struct PageParagraph: Identifiable, Sendable {
    /// Zero-based page and paragraph.
    let page: Int
    let index: Int
    let text: String
    /// In canvas coordinates.
    let rect: CGRect

    var id: String { "\(page)-\(index)" }
    /// How the AI cites it: [p3¶2] (one-based).
    var label: String { "[p\(page + 1)¶\(index + 1)]" }
}

/// Reads a page into paragraphs: PDF text where the page has it, otherwise
/// the handwriting and text read with Vision.
@MainActor
enum PageParagraphs {
    static func paragraphs(onPage page: Int, of content: NoteContent) async -> [PageParagraph] {
        let background = content.makeBackground()
        let rects = background.layout.pageRects
        guard rects.indices.contains(page) else { return [] }
        let pageRect = rects[page]
        if case let .pdf(index) = background.pages[page], let pdf = content.pdf {
            let lines = pdf.lines(onPage: index, pageRect: pageRect)
            if !lines.isEmpty {
                return group(lines, page: page)
            }
        }
        let lines = await Task.detached(priority: .userInitiated) {
            readLines(page: page, content: content, background: background, pageRect: pageRect)
        }.value
        return group(lines, page: page)
    }

    /// Lines close together become one paragraph.
    static func group(_ lines: [(text: String, rect: CGRect)], page: Int) -> [PageParagraph] {
        guard !lines.isEmpty else { return [] }
        let heights: [CGFloat] = lines.map(\.rect.height).sorted()
        let typical: CGFloat = max(heights[heights.count / 2], 6)
        var result: [PageParagraph] = []
        var texts: [String] = []
        var box = CGRect.null
        var lastBottom: CGFloat = -1
        func flush() {
            guard !texts.isEmpty else { return }
            result.append(PageParagraph(page: page, index: result.count, text: texts.joined(separator: " "), rect: box))
            texts = []
            box = .null
        }
        for line in lines {
            if lastBottom >= 0, line.rect.minY - lastBottom > typical * 0.9 { flush() }
            texts.append(line.text)
            box = box.union(line.rect)
            lastBottom = line.rect.maxY
        }
        flush()
        return result
    }

    /// Text lines read from a picture of the page, in canvas coordinates.
    private nonisolated static func readLines(page: Int, content: NoteContent, background: NoteBackground, pageRect: CGRect) -> [(text: String, rect: CGRect)] {
        let picture = ThumbnailRenderer.image(
            ofPage: page,
            drawing: content.drawing,
            elements: content.metadata.elements ?? [],
            imageDirectory: content.imageDirectory,
            background: background,
            scale: 1
        )
        guard let cgImage = picture.cgImage else { return [] }
        return InkOCR.lines(in: cgImage, mappedTo: pageRect)
    }
}
