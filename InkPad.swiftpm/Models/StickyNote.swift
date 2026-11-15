import PencilKit
import SwiftUI

/// A sticky note on a page: typed text and handwriting on colored paper.
/// It can be folded to a small square, grouped by name, and turned into a
/// Planner task linked to its page.
struct StickyNote: Codable, Equatable {
    enum Tint: String, Codable, CaseIterable, Identifiable {
        case yellow, pink, blue, green, orange, purple

        var id: Self { self }

        var title: String {
            switch self {
            case .yellow: "Yellow"
            case .pink: "Pink"
            case .blue: "Blue"
            case .green: "Green"
            case .orange: "Orange"
            case .purple: "Purple"
            }
        }

        var uiColor: UIColor {
            switch self {
            case .yellow: UIColor(red: 1.00, green: 0.93, blue: 0.55, alpha: 1)
            case .pink: UIColor(red: 1.00, green: 0.78, blue: 0.84, alpha: 1)
            case .blue: UIColor(red: 0.74, green: 0.87, blue: 1.00, alpha: 1)
            case .green: UIColor(red: 0.78, green: 0.94, blue: 0.74, alpha: 1)
            case .orange: UIColor(red: 1.00, green: 0.82, blue: 0.60, alpha: 1)
            case .purple: UIColor(red: 0.86, green: 0.80, blue: 1.00, alpha: 1)
            }
        }

        var color: Color { Color(uiColor) }
    }

    var tint: Tint
    var text: String
    /// Handwriting (PKDrawing data) in the note's own coordinates: the top
    /// left of the sticky is 0,0 and it is `StickyNote.inkSize` big.
    var ink: Data?
    /// Folded to a small square on the page.
    var isFolded: Bool
    /// Stickies with the same group name are listed together.
    var group: String?
    /// The Planner task made from it.
    var taskID: UUID?

    /// The size handwriting is written at; the sticky scales it to fit.
    static let inkSize = CGSize(width: 300, height: 300)
    static let defaultSize = CGSize(width: 200, height: 200)
    static let foldedSize: CGFloat = 44

    init(tint: Tint = .yellow) {
        self.tint = tint
        text = ""
        ink = nil
        isFolded = false
        group = nil
        taskID = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tint = container.value(.tint, or: Tint.yellow)
        text = container.value(.text, or: "")
        ink = container.value(.ink, or: nil)
        isFolded = container.value(.isFolded, or: false)
        group = container.value(.group, or: nil)
        taskID = container.value(.taskID, or: nil)
    }

    var drawing: PKDrawing? {
        guard let ink else { return nil }
        return try? PKDrawing(data: ink)
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (drawing?.strokes.isEmpty ?? true)
    }

    /// The first line of the text, for lists and task titles.
    var headline: String {
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// Where it shows on the page: the whole note, or a small square when folded.
    static func visibleFrame(_ frame: CGRect, folded: Bool) -> CGRect {
        guard folded else { return frame }
        return CGRect(x: frame.minX, y: frame.minY, width: foldedSize, height: foldedSize)
    }

    /// Draws the sticky (for the live view, thumbnails and PDF export).
    func draw(in rect: CGRect, context: CGContext) {
        let folded = isFolded
        let shape = UIBezierPath(roundedRect: rect, cornerRadius: folded ? 8 : 4)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.18).cgColor)
        tint.uiColor.setFill()
        shape.fill()
        context.restoreGState()
        // A darker strip at the top, like the glued edge.
        let stripHeight: CGFloat = folded ? 6 : 14
        let strip = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: stripHeight)
        tint.uiColor.withAlphaComponent(1).mixed(with: .black, amount: 0.08).setFill()
        UIBezierPath(roundedRect: strip, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 4, height: 4)).fill()
        if folded {
            let symbol = taskID == nil ? "note.text" : "checklist"
            if let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)) {
                let tinted = image.withTintColor(UIColor.black.withAlphaComponent(0.55), renderingMode: .alwaysOriginal)
                let size = tinted.size
                tinted.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + 2, width: size.width, height: size.height))
            }
            return
        }
        var top = rect.minY + stripHeight + 6
        if let group, !group.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.45),
            ]
            NSAttributedString(string: group.uppercased(), attributes: attributes)
                .draw(in: CGRect(x: rect.minX + 10, y: top, width: rect.width - 20, height: 14))
            top += 16
        }
        let body = CGRect(x: rect.minX + 10, y: top, width: rect.width - 20, height: rect.maxY - top - 8)
        var inkArea = CGRect(x: rect.minX + 4, y: top, width: rect.width - 8, height: rect.maxY - top - 4)
        if !text.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Noteworthy-Light", size: 17) ?? UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.black.withAlphaComponent(0.85),
                .paragraphStyle: paragraph,
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            string.draw(with: body, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            // Handwriting goes below the text.
            let used = string.boundingRect(with: body.size, options: [.usesLineFragmentOrigin], context: nil).height
            let textBottom: CGFloat = min(top + used.rounded(.up) + 4, rect.maxY - 24)
            inkArea = CGRect(x: rect.minX + 4, y: textBottom, width: rect.width - 8, height: rect.maxY - textBottom - 4)
        }
        if let drawing, !drawing.strokes.isEmpty {
            let inkRect = CGRect(origin: .zero, size: Self.inkSize)
            let image = InkSnapshot.snapshot(of: drawing, from: inkRect, scale: 2)
            let side: CGFloat = min(inkArea.width, inkArea.height)
            let inkFrame = CGRect(x: inkArea.midX - side / 2, y: inkArea.midY - side / 2, width: side, height: side)
            image.draw(in: inkFrame)
        }
        if taskID != nil, let check = UIImage(systemName: "checklist", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)) {
            let tinted = check.withTintColor(UIColor.black.withAlphaComponent(0.5), renderingMode: .alwaysOriginal)
            tinted.draw(at: CGPoint(x: rect.maxX - tinted.size.width - 8, y: rect.minY + stripHeight + 4))
        }
    }
}

extension UIColor {
    /// This color moved `amount` (0...1) of the way towards `other`.
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let keep: CGFloat = 1 - amount
        return UIColor(red: r1 * keep + r2 * amount, green: g1 * keep + g2 * amount, blue: b1 * keep + b2 * amount, alpha: a1)
    }
}
