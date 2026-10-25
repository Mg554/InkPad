import PencilKit
import UIKit
import Vision

/// Reads a handwritten note's pages for slides: the writing and printed text
/// on each page (recognized on the iPad with Vision) and a picture of it.
enum NoteReader {
    struct Page: Sendable {
        let text: String
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
        guard hasContent else { return Page(text: "", image: nil) }
        let picture = ThumbnailRenderer.image(
            ofPage: index,
            drawing: content.drawing,
            elements: elements,
            imageDirectory: content.imageDirectory,
            background: background,
            scale: 1
        )
        let text = picture.cgImage.map { recognizeText(in: $0) } ?? ""
        return Page(text: text, image: wantsImage ? picture.jpegData(compressionQuality: 0.75) : nil)
    }

    /// Lines of text, top to bottom.
    static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return ""
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
