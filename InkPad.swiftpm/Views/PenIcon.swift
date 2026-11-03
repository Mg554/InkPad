import SwiftUI

/// An upright pen in a modern, three-dimensional style: a pearl-white
/// barrel shaded like a cylinder, a metal collar, a band of the ink's color,
/// and a tip shaped like the real tool, lit from the left.
struct PenIcon: View {
    let tool: DrawingTool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let barrel = CGRect(x: width * 0.2, y: height * 0.44, width: width * 0.6, height: height * 0.56)
            let left = barrel.minX
            let right = barrel.maxX
            let base = barrel.minY
            let top = CGPoint(x: width / 2, y: height * 0.02)

            // Barrel: pearl white, shaded round, with a band of the ink's color.
            let barrelPath = Path(roundedRect: barrel, cornerRadii: RectangleCornerRadii(topLeading: 2, bottomLeading: 0, bottomTrailing: 0, topTrailing: 2))
            context.fill(barrelPath, with: .color(Color(white: 0.97)))
            shade(barrelPath, across: barrel, in: context)
            let band = CGRect(x: left, y: base + height * 0.17, width: barrel.width, height: height * 0.075)
            context.fill(Path(band), with: .color(color))
            shade(Path(band), across: barrel, in: context)

            switch tool {
            case .pen, .monoline:
                // A tapered metal cone with an ink-colored point.
                var cone = Path()
                cone.move(to: CGPoint(x: left, y: base))
                cone.addLine(to: CGPoint(x: width / 2 - 1.6, y: height * 0.1))
                cone.addLine(to: CGPoint(x: width / 2 + 1.6, y: height * 0.1))
                cone.addLine(to: CGPoint(x: right, y: base))
                cone.closeSubpath()
                metal(cone, across: barrel, in: context)
                let pointHeight = tool == .monoline ? 0.12 : 0.16
                let point = triangle(top, width: width * 0.15, height: height * pointHeight)
                context.fill(point, with: .color(color))
                shade(point, across: barrel, in: context)

            case .pencil:
                // Sharpened wood and graphite.
                var wood = Path()
                wood.move(to: CGPoint(x: left, y: base))
                wood.addLine(to: top)
                wood.addLine(to: CGPoint(x: right, y: base))
                wood.closeSubpath()
                context.fill(wood, with: .color(Color(red: 0.95, green: 0.83, blue: 0.64)))
                shade(wood, across: barrel, in: context)
                let lead = triangle(top, width: width * 0.2, height: height * 0.14)
                context.fill(lead, with: .color(color))
                shade(lead, across: barrel, in: context)

            case .fountainPen, .quill:
                // A polished nib with a slit and breather hole.
                var nib = Path()
                nib.move(to: CGPoint(x: left, y: base))
                nib.addQuadCurve(to: top, control: CGPoint(x: left - width * 0.08, y: height * 0.18))
                nib.addQuadCurve(to: CGPoint(x: right, y: base), control: CGPoint(x: right + width * 0.08, y: height * 0.18))
                nib.closeSubpath()
                if tool == .quill {
                    context.fill(nib, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.62, green: 0.47, blue: 0.20), Color(red: 0.98, green: 0.86, blue: 0.52), Color(red: 0.70, green: 0.54, blue: 0.24)]),
                        startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0)
                    ))
                } else {
                    metal(nib, across: barrel, in: context)
                }
                var slit = Path()
                slit.move(to: top)
                slit.addLine(to: CGPoint(x: width / 2, y: height * 0.26))
                context.stroke(slit, with: .color(.black.opacity(0.55)), lineWidth: 0.8)
                context.fill(Path(ellipseIn: CGRect(x: width / 2 - 1.5, y: height * 0.26, width: 3, height: 3)), with: .color(.black.opacity(0.6)))
                let ring = Path(CGRect(x: left, y: base - 2, width: barrel.width, height: 2.5))
                context.fill(ring, with: .color(color))
                shade(ring, across: barrel, in: context)

            case .marker, .highlighter:
                // A metal collar and a chisel tip.
                var collar = Path()
                collar.move(to: CGPoint(x: left, y: base))
                collar.addLine(to: CGPoint(x: left + width * 0.06, y: height * 0.24))
                collar.addLine(to: CGPoint(x: right - width * 0.06, y: height * 0.24))
                collar.addLine(to: CGPoint(x: right, y: base))
                collar.closeSubpath()
                metal(collar, across: barrel, in: context)
                var chisel = Path()
                chisel.move(to: CGPoint(x: left + width * 0.1, y: height * 0.24))
                chisel.addLine(to: CGPoint(x: left + width * 0.1, y: height * 0.1))
                chisel.addLine(to: CGPoint(x: right - width * 0.1, y: height * 0.02))
                chisel.addLine(to: CGPoint(x: right - width * 0.1, y: height * 0.24))
                chisel.closeSubpath()
                context.fill(chisel, with: .color(tool == .highlighter ? color.opacity(0.85) : color))
                shade(chisel, across: barrel, in: context)

            case .crayon:
                var crayon = Path()
                crayon.move(to: CGPoint(x: left, y: base))
                crayon.addLine(to: CGPoint(x: left + width * 0.08, y: height * 0.14))
                crayon.addQuadCurve(to: CGPoint(x: right - width * 0.08, y: height * 0.14), control: CGPoint(x: width / 2, y: 0))
                crayon.addLine(to: CGPoint(x: right, y: base))
                crayon.closeSubpath()
                context.fill(crayon, with: .color(color))
                shade(crayon, across: barrel, in: context)

            case .watercolor:
                let ferrule = Path(CGRect(x: left + width * 0.04, y: height * 0.3, width: barrel.width - width * 0.08, height: base - height * 0.3))
                metal(ferrule, across: barrel, in: context)
                var brush = Path()
                brush.move(to: CGPoint(x: left + width * 0.04, y: height * 0.3))
                brush.addQuadCurve(to: top, control: CGPoint(x: left, y: height * 0.1))
                brush.addQuadCurve(to: CGPoint(x: right - width * 0.04, y: height * 0.3), control: CGPoint(x: right, y: height * 0.1))
                brush.closeSubpath()
                context.fill(brush, with: .color(color))
                shade(brush, across: barrel, in: context)

            case .eraser, .text, .lasso, .laser:
                break
            }

            // A soft outline keeps the white barrel visible on light bars.
            context.stroke(barrelPath, with: .color(.black.opacity(0.12)), lineWidth: 0.6)
        }
    }

    /// Lights a shape like a cylinder: a highlight on the left, shadow on the
    /// right edge. Works on any color.
    private func shade(_ path: Path, across rect: CGRect, in context: GraphicsContext) {
        context.fill(path, with: .linearGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.10), location: 0),
                .init(color: .white.opacity(0.55), location: 0.28),
                .init(color: .white.opacity(0.0), location: 0.55),
                .init(color: .black.opacity(0.28), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
    }

    /// Brushed steel.
    private func metal(_ path: Path, across rect: CGRect, in context: GraphicsContext) {
        context.fill(path, with: .linearGradient(
            Gradient(colors: [Color(white: 0.55), Color(white: 0.92), Color(white: 0.72), Color(white: 0.45)]),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
    }

    private func triangle(_ top: CGPoint, width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        path.move(to: top)
        path.addLine(to: CGPoint(x: top.x - width / 2, y: top.y + height))
        path.addLine(to: CGPoint(x: top.x + width / 2, y: top.y + height))
        path.closeSubpath()
        return path
    }
}
