import SwiftUI

enum SlideExportError: LocalizedError {
    case couldNotCreate

    var errorDescription: String? {
        "The PDF could not be created."
    }
}

/// Writes a deck as a PDF, one 16:9 page per slide, with text kept sharp.
@MainActor
enum SlideExporter {
    static func pdf(for deck: SlideDeck, images: [String: UIImage]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(deck.title, fallback: "Slides"))
            .appendingPathExtension("pdf")
        var box = CGRect(origin: .zero, size: SlideView.designSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw SlideExportError.couldNotCreate
        }
        for (index, slide) in deck.slides.enumerated() {
            let renderer = ImageRenderer(content: SlideCanvas(
                slide: slide,
                theme: deck.theme,
                image: slide.imageFile.flatMap { images[$0] },
                number: index + 1,
                total: deck.slides.count
            ))
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }
}
