import UIKit

/// Draws the stacked pages behind the ink. Backed by a tiled layer so paper and
/// PDF pages stay sharp when zoomed and long notes do not need one huge bitmap.
final class PageBackgroundView: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }

    // Tiles are drawn off the main thread, so the background is lock-protected.
    private let lock = NSLock()
    private var background: NoteBackground?

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

    func configure(_ background: NoteBackground) {
        lock.withLock { self.background = background }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let background = lock.withLock({ self.background })
        else { return }
        for (index, pageRect) in background.layout.pageRects.enumerated() where pageRect.intersects(rect) {
            background.drawPage(at: index, in: context)
        }
    }
}
