import SwiftUI

enum SlideExportError: LocalizedError {
    case couldNotCreate

    var errorDescription: String? {
        "The file could not be created."
    }
}

/// Writes a deck as a PDF, pictures or an outline. (`PPTXExporter` writes
/// PowerPoint files.)
@MainActor
enum SlideExporter {
    /// One 16:9 page per slide, with text kept sharp.
    static func pdf(for deck: SlideDeck, images: [String: UIImage]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(deck.title, fallback: "Slides"))
            .appendingPathExtension("pdf")
        var box = CGRect(origin: .zero, size: SlideView.designSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw SlideExportError.couldNotCreate
        }
        for index in deck.slides.indices {
            let renderer = ImageRenderer(content: canvas(deck, index: index, images: images))
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    /// Each slide as a 1920 × 1080 PNG picture.
    static func pictures(for deck: SlideDeck, images: [String: UIImage]) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(deck.title, fallback: "Slides") + " (Pictures)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in deck.slides.indices {
            let renderer = ImageRenderer(content: canvas(deck, index: index, images: images))
            renderer.scale = 1.5
            guard let png = renderer.uiImage?.pngData() else { throw SlideExportError.couldNotCreate }
            let number = String(index + 1)
            let padded = String(repeating: "0", count: max(0, 2 - number.count)) + number
            let url = folder.appendingPathComponent("Slide \(padded).png")
            try png.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }

    /// The deck's words as Markdown: a heading per slide, its points, and
    /// the speaker notes. Opens in any text editor, or as an InkPad note.
    static func outline(for deck: SlideDeck) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(deck.title, fallback: "Slides"))
            .appendingPathExtension("md")
        try Data(outlineText(for: deck).utf8).write(to: url, options: .atomic)
        return url
    }

    static func outlineText(for deck: SlideDeck) -> String {
        var lines = ["# \(deck.title)", ""]
        for (index, slide) in deck.slides.enumerated() {
            if slide.layout == .quote {
                lines.append("## \(index + 1). Quote")
                lines.append("> \(slide.title)")
                if !slide.subtitle.isEmpty { lines.append("> — \(slide.subtitle)") }
            } else {
                lines.append("## \(index + 1). \(slide.title)")
                if !slide.subtitle.isEmpty { lines.append("*\(slide.subtitle)*") }
            }
            let bullets = slide.visibleBullets
            if !bullets.isEmpty {
                lines.append("")
                for (position, bullet) in bullets.enumerated() {
                    lines.append(slide.layout == .agenda ? "\(position + 1). \(bullet)" : "- \(bullet)")
                }
            }
            let notes = slide.speakerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                lines.append("")
                lines.append("**Speaker notes:** " + notes.replacingOccurrences(of: "\n", with: " "))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func canvas(_ deck: SlideDeck, index: Int, images: [String: UIImage]) -> SlideCanvas {
        let slide = deck.slides[index]
        return SlideCanvas(
            slide: slide,
            theme: deck.theme,
            image: slide.imageFile.flatMap { images[$0] },
            number: index + 1,
            total: deck.slides.count
        )
    }
}
