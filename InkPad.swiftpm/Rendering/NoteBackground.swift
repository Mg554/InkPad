import CoreGraphics

/// What is drawn underneath the ink: the PDF's pages first, then template paper.
/// Shared by the canvas, thumbnails and PDF export so they always match.
struct NoteBackground: Equatable {
    /// A4 in PDF points, used when exporting template pages.
    static let templateExportSize = CGSize(width: 595.28, height: 841.89)

    let template: PageTemplate
    let pdf: PDFBackground?
    let layout: PageLayout

    init(template: PageTemplate, templatePageCount: Int, pdf: PDFBackground?) {
        self.template = template
        self.pdf = pdf
        var sizes: [CGSize] = []
        for index in 0..<(pdf?.pageCount ?? 0) {
            let size = pdf?.displaySize(ofPage: index) ?? .zero
            guard size.width > 0, size.height > 0 else {
                sizes.append(PageLayout.templatePageSize)
                continue
            }
            sizes.append(CGSize(width: PageLayout.pageWidth, height: PageLayout.pageWidth * size.height / size.width))
        }
        sizes += Array(repeating: PageLayout.templatePageSize, count: max(templatePageCount, 0))
        layout = PageLayout(pageSizes: sizes)
    }

    func isPDFPage(_ index: Int) -> Bool {
        index < (pdf?.pageCount ?? 0)
    }

    func drawPage(at index: Int, in context: CGContext) {
        let rect = layout.pageRects[index]
        if let pdf, isPDFPage(index) {
            pdf.draw(page: index, in: rect, context: context)
        } else {
            TemplateRenderer.drawPage(template, in: rect, context: context)
        }
    }

    /// Page size for export: the PDF page's own size, or A4 for template pages.
    func exportSize(ofPage index: Int) -> CGSize {
        if let pdf, isPDFPage(index) {
            return pdf.displaySize(ofPage: index)
        }
        return Self.templateExportSize
    }

    static func == (lhs: NoteBackground, rhs: NoteBackground) -> Bool {
        lhs.template == rhs.template && lhs.pdf === rhs.pdf && lhs.layout == rhs.layout
    }
}
