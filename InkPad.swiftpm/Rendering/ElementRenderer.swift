import UIKit

/// Draws text boxes and images for thumbnails and PDF export, matching the
/// live editor's layout.
enum ElementRenderer {
    static func draw(_ elements: [PageElement], on pageRect: CGRect, imageDirectory: URL, context: CGContext) {
        let visible = elements.filter { $0.frame.intersects(pageRect) }
        guard !visible.isEmpty else { return }
        UIGraphicsPushContext(context)
        context.saveGState()
        context.clip(to: pageRect)
        defer {
            context.restoreGState()
            UIGraphicsPopContext()
        }
        for element in visible {
            switch element.content {
            case let .text(rtf):
                guard let text = TextBoxStyle.attributedString(fromRTF: rtf) else { continue }
                let inset = TextBoxStyle.padding
                text.draw(
                    with: element.frame.insetBy(dx: inset, dy: inset),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
            case let .image(file):
                guard isPlainFileName(file),
                      let image = UIImage(contentsOfFile: imageDirectory.appendingPathComponent(file).path)
                else { continue }
                image.draw(in: element.frame)
            case let .sticky(note):
                note.draw(in: StickyNote.visibleFrame(element.frame, folded: note.isFolded), context: context)
            case let .comment(comment):
                // The same badge the editor shows (CommentPinView).
                let image = UIImage(systemName: comment.isResolved ?? false ? "checkmark.seal.fill" : "bubble.left.and.bubble.right.fill")?
                    .withTintColor(comment.isResolved ?? false ? .systemGray : .systemYellow, renderingMode: .alwaysOriginal)
                image?.draw(in: element.frame)
            }
        }
    }
}
