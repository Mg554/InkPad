import PencilKit
import UIKit

/// Reads a handwritten note's pages for slides: the writing and printed text
/// on each page (recognized on the iPad with Vision) and a picture of it.
enum NoteReader {
    struct Page: Sendable {
        let text: String
        /// Recognized lines with their position on the page (0…1).
        let hits: [OCRHit]
        /// A JPEG of the page, when asked for and the page has something on it.
        let image: Data?
    }

    /// Safe to call off the main thread.
    static func read(page index: Int, of content: NoteContent, background: NoteBackground, wantsImage: Bool) -> Page {
        let rect = background.layout.pageRects[index]
        let elements = content.metadata.elements ?? []
        let hasContent = content.drawing.bounds.intersects(rect)
            || elements.contains { $0.frame.intersects(rect) }
            || background.pages[index] != .paper
        guard hasContent else { return Page(text: "", hits: [], image: nil) }
        let picture = ThumbnailRenderer.image(
            ofPage: index,
            drawing: content.drawing,
            elements: elements,
            imageDirectory: content.imageDirectory,
            background: background,
            scale: 1
        )
        let lines = picture.cgImage.map { InkOCR.lines(in: $0) } ?? []
        let text = InkOCR.text(of: lines)
        let pageRect = background.layout.pageRects[index]
        let w = max(pageRect.width, 1)
        let h = max(pageRect.height, 1)
        let hits: [OCRHit] = lines.compactMap { line in
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let rect = CGRect(
                x: line.box.minX / w,
                y: line.box.minY / h,
                width: line.box.width / w,
                height: line.box.height / h
            )
            return OCRHit(text: line.text, page: index, rect: rect)
        }
        return Page(text: text, hits: hits, image: wantsImage ? picture.jpegData(compressionQuality: 0.75) : nil)
    }
}
