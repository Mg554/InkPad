import UIKit

/// Draws page paper and its template pattern. Shared by the live canvas
/// background and the library thumbnails so both always match.
enum TemplateRenderer {
    static let paperColor = UIColor.white
    static let lineColor = UIColor(red: 0.64, green: 0.76, blue: 0.90, alpha: 1)
    static let marginColor = UIColor(red: 0.93, green: 0.58, blue: 0.58, alpha: 1)

    static let lineSpacing: CGFloat = 32
    static let gridSpacing: CGFloat = 24
    static let lineTopInset: CGFloat = 96
    static let marginInset: CGFloat = 80

    static func drawPage(_ template: PageTemplate, in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(paperColor.cgColor)
        context.fill(rect)
        context.setLineWidth(0.75)
        context.setStrokeColor(lineColor.cgColor)
        context.setFillColor(lineColor.cgColor)

        switch template {
        case .blank:
            break

        case .lined:
            var y = rect.minY + lineTopInset
            while y < rect.maxY - lineSpacing {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += lineSpacing
            }
            context.strokePath()
            context.setStrokeColor(marginColor.cgColor)
            context.move(to: CGPoint(x: rect.minX + marginInset, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.minX + marginInset, y: rect.maxY))
            context.strokePath()

        case .grid:
            var x = rect.minX + gridSpacing
            while x < rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += gridSpacing
            }
            var y = rect.minY + gridSpacing
            while y < rect.maxY {
                context.move(to: CGPoint(x: rect.minX, y: y))
                context.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += gridSpacing
            }
            context.strokePath()

        case .dotted:
            let radius: CGFloat = 1.2
            var y = rect.minY + gridSpacing
            while y < rect.maxY {
                var x = rect.minX + gridSpacing
                while x < rect.maxX {
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += gridSpacing
                }
                y += gridSpacing
            }
        }
    }
}
