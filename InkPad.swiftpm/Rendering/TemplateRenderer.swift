import UIKit

/// Draws page paper and its template pattern. Shared by the live canvas
/// background, thumbnails, the template gallery and PDF export.
enum TemplateRenderer {
    static let lineSpacing: CGFloat = 32
    static let collegeSpacing: CGFloat = 24
    static let gridSpacing: CGFloat = 24
    static let lineTopInset: CGFloat = 96
    static let marginInset: CGFloat = 80

    static func drawPage(_ template: PageTemplate, paper: PaperColor, in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let rgb = paper.rgb
        context.setFillColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        context.fill(rect)

        let lineColor = paper.isDark
            ? UIColor(white: 1, alpha: 0.28)
            : UIColor(red: 0.64, green: 0.76, blue: 0.90, alpha: 1)
        let marginColor = UIColor(red: 0.93, green: 0.50, blue: 0.50, alpha: paper.isDark ? 0.7 : 1)
        context.setLineWidth(0.75)
        context.setStrokeColor(lineColor.cgColor)
        context.setFillColor(lineColor.cgColor)

        switch template {
        case .blank:
            break

        case .lined:
            horizontalLines(in: rect, from: rect.minY + lineTopInset, spacing: lineSpacing, context: context)
            context.strokePath()
            margin(in: rect, color: marginColor, context: context)

        case .collegeRule:
            horizontalLines(in: rect, from: rect.minY + lineTopInset, spacing: collegeSpacing, context: context)
            context.strokePath()
            margin(in: rect, color: marginColor, context: context)

        case .manuscript:
            // Handwriting practice: solid top line, dashed midline, solid baseline.
            let rowHeight: CGFloat = 48
            let rowGap: CGFloat = 24
            var top = rect.minY + lineTopInset
            while top + rowHeight < rect.maxY - 24 {
                line(from: rect.minX, to: rect.maxX, y: top, context: context)
                line(from: rect.minX, to: rect.maxX, y: top + rowHeight, context: context)
                context.strokePath()
                context.saveGState()
                context.setLineDash(phase: 0, lengths: [6, 5])
                line(from: rect.minX, to: rect.maxX, y: top + rowHeight / 2, context: context)
                context.strokePath()
                context.restoreGState()
                top += rowHeight + rowGap
            }
            margin(in: rect, color: marginColor, context: context)

        case .grid:
            var x = rect.minX + gridSpacing
            while x < rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += gridSpacing
            }
            horizontalLines(in: rect, from: rect.minY + gridSpacing, spacing: gridSpacing, context: context)
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

        case .hexagon:
            hexagons(in: rect, radius: 14, context: context)
            context.strokePath()

        case .cornell:
            let header: CGFloat = 120
            let summary: CGFloat = 200
            let cue: CGFloat = 200
            let notesTop = rect.minY + header
            let notesBottom = rect.maxY - summary
            var y = notesTop + 28
            while y < notesBottom - 4 {
                line(from: rect.minX + cue, to: rect.maxX, y: y, context: context)
                y += 28
            }
            context.strokePath()
            context.setLineWidth(1.5)
            line(from: rect.minX, to: rect.maxX, y: notesTop, context: context)
            line(from: rect.minX, to: rect.maxX, y: notesBottom, context: context)
            context.move(to: CGPoint(x: rect.minX + cue, y: notesTop))
            context.addLine(to: CGPoint(x: rect.minX + cue, y: notesBottom))
            context.strokePath()

        case .twoColumn, .threeColumn:
            let columns: CGFloat = template == .twoColumn ? 2 : 3
            let gap: CGFloat = 28
            let side: CGFloat = 40
            let width = (rect.width - side * 2 - gap * (columns - 1)) / columns
            var y = rect.minY + lineTopInset
            while y < rect.maxY - lineSpacing {
                for column in 0..<Int(columns) {
                    let x = rect.minX + side + CGFloat(column) * (width + gap)
                    line(from: x, to: x + width, y: y, context: context)
                }
                y += lineSpacing
            }
            context.strokePath()
        }
    }

    private static func line(from x0: CGFloat, to x1: CGFloat, y: CGFloat, context: CGContext) {
        context.move(to: CGPoint(x: x0, y: y))
        context.addLine(to: CGPoint(x: x1, y: y))
    }

    private static func horizontalLines(in rect: CGRect, from top: CGFloat, spacing: CGFloat, context: CGContext) {
        var y = top
        while y < rect.maxY - spacing / 2 {
            line(from: rect.minX, to: rect.maxX, y: y, context: context)
            y += spacing
        }
    }

    private static func margin(in rect: CGRect, color: UIColor, context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.move(to: CGPoint(x: rect.minX + marginInset, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.minX + marginInset, y: rect.maxY))
        context.strokePath()
    }

    /// Pointy-top honeycomb clipped to the page.
    private static func hexagons(in rect: CGRect, radius: CGFloat, context: CGContext) {
        context.clip(to: rect)
        let width = sqrt(3) * radius
        let rowStep = radius * 1.5
        var row = 0
        var centerY = rect.minY
        while centerY < rect.maxY + radius {
            var centerX = rect.minX + (row.isMultiple(of: 2) ? 0 : width / 2)
            while centerX < rect.maxX + width {
                for corner in 0..<6 {
                    let angle = CGFloat.pi / 3 * CGFloat(corner) - CGFloat.pi / 2
                    let point = CGPoint(x: centerX + radius * cos(angle), y: centerY + radius * sin(angle))
                    if corner == 0 { context.move(to: point) } else { context.addLine(to: point) }
                }
                context.closePath()
                centerX += width
            }
            centerY += rowStep
            row += 1
        }
    }
}
