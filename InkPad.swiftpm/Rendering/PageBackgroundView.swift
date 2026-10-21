import UIKit

/// Draws the stacked pages behind the ink. Backed by a tiled layer so the
/// template stays sharp when zoomed and long notes do not need one huge bitmap.
final class PageBackgroundView: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }

    private var template: PageTemplate = .blank
    private var pageCount = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        if let tiledLayer = layer as? CATiledLayer {
            tiledLayer.levelsOfDetail = 4
            tiledLayer.levelsOfDetailBias = 4
            tiledLayer.tileSize = CGSize(width: 512, height: 512)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(template: PageTemplate, pageCount: Int) {
        guard template != self.template || pageCount != self.pageCount else { return }
        self.template = template
        self.pageCount = pageCount
        setNeedsDisplay()
    }

    // Called by CATiledLayer for each visible tile, possibly off the main thread.
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for index in 0..<pageCount {
            let pageRect = PageLayout.pageRect(at: index)
            guard pageRect.intersects(rect) else { continue }
            TemplateRenderer.drawPage(template, in: pageRect, context: context)
        }
    }
}
