import CoreGraphics

/// What is drawn underneath the ink: the PDF's pages first, then template paper.
/// Shared by the canvas, thumbnails and PDF export so they always match.
struct NoteBackground: Equatable {
    /// A4 in PDF points, used when exporting template pages.
    static let templateExportSize = CGSize(width: 595.28, height: 841.89)

    let template: PageTemplate
    let paper: PaperColor
    let pages: [PageSource]
    let pdf: PDFBackground?
    let layout: PageLayout

    init(template: PageTemplate, paper: PaperColor, pages: [PageSource], pdf: PDFBackground?) {
        self.template = template
        self.paper = paper
        self.pages = pages
        self.pdf = pdf
        layout = PageLayout(pageSizes: pages.map { source in
            guard case let .pdf(index) = source, let size = pdf?.displaySize(ofPage: index),
                  size.width > 0, size.height > 0
            else { return PageLayout.templatePageSize }
            return CGSize(width: PageLayout.pageWidth, height: PageLayout.pageWidth * size.height / size.width)
        })
    }

    /// The PDF page shown on this page, if it is a readable PDF page.
    private func pdfPage(at index: Int) -> Int? {
        guard pages.indices.contains(index), case let .pdf(pdfIndex) = pages[index],
              let pdf, pdfIndex >= 0, pdfIndex < pdf.pageCount
        else { return nil }
        return pdfIndex
    }

    /// - Parameter includePaper: `false` draws paper pages as plain white
    ///   (PDF pages are always drawn).
    func drawPage(at index: Int, in context: CGContext, includePaper: Bool = true) {
        let rect = layout.pageRects[index]
        if let pdf, let pdfIndex = pdfPage(at: index) {
            pdf.draw(page: pdfIndex, in: rect, context: context)
        } else if includePaper {
            TemplateRenderer.drawPage(template, paper: paper, in: rect, context: context)
        } else {
            TemplateRenderer.drawPage(.blank, paper: .white, in: rect, context: context)
        }
    }

    /// Page size for export: the PDF page's own size, or A4 for paper pages.
    func exportSize(ofPage index: Int) -> CGSize {
        if let pdf, let pdfIndex = pdfPage(at: index) {
            return pdf.displaySize(ofPage: pdfIndex)
        }
        return Self.templateExportSize
    }

    static func == (lhs: NoteBackground, rhs: NoteBackground) -> Bool {
        lhs.template == rhs.template && lhs.paper == rhs.paper && lhs.pages == rhs.pages && lhs.pdf === rhs.pdf
    }
}
