import PencilKit
import UIKit

struct PDFExportOptions {
    var includePaper = true
    var addMargins = false
    /// Zero-based, inclusive. `nil` exports every page.
    var pageRange: ClosedRange<Int>?
    /// Empty means no password.
    var password = ""
}

/// Writes a note as a PDF: PDF pages stay vector, ink is added as an image.
/// Safe to call off the main thread.
enum PDFExporter {
    /// Ink resolution relative to canvas points.
    static let inkScale: CGFloat = 2
    static let marginFraction: CGFloat = 0.06

    static func export(_ content: NoteContent, title: String, options: PDFExportOptions = PDFExportOptions()) throws -> URL {
        let background = content.makeBackground()
        let elements = content.metadata.elements ?? []
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(title, fallback: "Note"))
            .appendingPathExtension("pdf")

        let format = UIGraphicsPDFRendererFormat()
        var info: [String: Any] = [kCGPDFContextTitle as String: title]
        if !options.password.isEmpty {
            info[kCGPDFContextUserPassword as String] = options.password
            info[kCGPDFContextOwnerPassword as String] = options.password
        }
        format.documentInfo = info
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: NoteBackground.templateExportSize),
            format: format
        )

        let pages = background.layout.pageRects.indices.filter { options.pageRange?.contains($0) ?? true }

        try renderer.writePDF(to: url) { context in
            for index in pages {
                autoreleasepool {
                    let pageRect = background.layout.pageRects[index]
                    let pageSize = background.exportSize(ofPage: index)
                    context.beginPage(withBounds: CGRect(origin: .zero, size: pageSize), pageInfo: [:])
                    let cgContext = context.cgContext
                    var scale = pageSize.width / pageRect.width
                    if options.addMargins {
                        cgContext.setFillColor(UIColor.white.cgColor)
                        cgContext.fill(CGRect(origin: .zero, size: pageSize))
                        let inset = pageSize.width * marginFraction
                        scale *= (pageSize.width - inset * 2) / pageSize.width
                        cgContext.translateBy(x: inset, y: (pageSize.height - pageRect.height * scale) / 2)
                    }
                    cgContext.scaleBy(x: scale, y: scale)
                    cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
                    background.drawPage(at: index, in: cgContext, includePaper: options.includePaper)
                    ElementRenderer.draw(elements, on: pageRect, imageDirectory: content.imageDirectory, context: cgContext)

                    guard content.drawing.bounds.intersects(pageRect) else { return }
                    var ink = UIImage()
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        ink = content.drawing.image(from: pageRect, scale: inkScale)
                    }
                    ink.draw(in: pageRect)
                }
            }
        }
        return url
    }
}
