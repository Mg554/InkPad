import SwiftUI

/// An upright pen in the style of Apple Notes' tools: a glossy black barrel
/// with a band of the ink's color, and a tip that shows the line it draws:
/// a fine point for the pen, a round tip for the even monoline, a nib for
/// the fountain pen, a broad gold nib for the quill, sharpened wood for the
/// pencil, wax for the crayon, a brush for watercolor, a bullet tip for the
/// marker and a wide chisel for the highlighter. Shaded to look round.
struct PenIcon: View {
    let tool: DrawingTool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let barrel = CGRect(x: width * 0.2, y: height * 0.46, width: width * 0.6, height: height * 0.54)
            let left = barrel.minX
            let right = barrel.maxX
            let base = barrel.minY
            let middle = width / 2
            let top = CGPoint(x: middle, y: height * 0.02)

            // Barrel and the band of the ink's color.
            let barrelPath = Path(barrel)
            glossyBlack(barrelPath, across: barrel, in: context)
            let band = Path(CGRect(x: left, y: base + height * 0.22, width: barrel.width, height: height * 0.06))
            context.fill(band, with: .color(color))
            shade(band, across: barrel, in: context)

            switch tool {
            case .pen:
                // A slim cone to a fine point: thin, pressure-sensitive lines.
                let cone = taper(from: left, to: right, base: base, tipY: height * 0.15, tipWidth: width * 0.16, center: middle)
                glossyBlack(cone, across: barrel, in: context)
                let point = triangle(top, width: width * 0.18, height: height * 0.15)
                context.fill(point, with: .color(color))
                shade(point, across: barrel, in: context)

            case .monoline:
                // A rounded tip: an even line that doesn't change with pressure.
                let cone = taper(from: left, to: right, base: base, tipY: height * 0.2, tipWidth: width * 0.3, center: middle)
                glossyBlack(cone, across: barrel, in: context)
                let tip = Path(roundedRect: CGRect(x: middle - width * 0.13, y: height * 0.05, width: width * 0.26, height: height * 0.17),
                               cornerRadius: width * 0.13)
                context.fill(tip, with: .color(color))
                shade(tip, across: barrel, in: context)

            case .fountainPen:
                // A steel nib with a slit and breather hole: lines that swell.
                let nib = nibShape(left: left, right: right, base: base, top: top, flare: -width * 0.1, height: height)
                metal(nib, across: barrel, in: context)
                slit(from: top, to: CGPoint(x: middle, y: height * 0.27), hole: true, in: context)
                ring(left: left, width: barrel.width, base: base, in: context)

            case .quill:
                // A broad gold nib cut square: thick downstrokes, thin sideways.
                var nib = Path()
                nib.move(to: CGPoint(x: left, y: base))
                nib.addQuadCurve(to: CGPoint(x: middle - width * 0.13, y: height * 0.07), control: CGPoint(x: left + width * 0.07, y: height * 0.22))
                nib.addLine(to: CGPoint(x: middle + width * 0.13, y: height * 0.02))
                nib.addQuadCurve(to: CGPoint(x: right, y: base), control: CGPoint(x: right - width * 0.07, y: height * 0.22))
                nib.closeSubpath()
                gold(nib, across: barrel, in: context)
                slit(from: CGPoint(x: middle, y: height * 0.05), to: CGPoint(x: middle, y: height * 0.27), hole: true, in: context)
                ring(left: left, width: barrel.width, base: base, in: context)

            case .pencil:
                // Sharpened wood and lead: a grainy line.
                let wood = triangle(top, width: barrel.width, height: base - top.y, baseY: base)
                context.fill(wood, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.80, green: 0.62, blue: 0.40), Color(red: 0.98, green: 0.87, blue: 0.68), Color(red: 0.78, green: 0.60, blue: 0.38)]),
                    startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0)
                ))
                let lead = triangle(top, width: width * 0.21, height: height * 0.14)
                context.fill(lead, with: .color(color))
                shade(lead, across: barrel, in: context)

            case .crayon:
                // A blunt cone of wax: a soft, textured line.
                var wax = Path()
                wax.move(to: CGPoint(x: left, y: base))
                wax.addLine(to: CGPoint(x: middle - width * 0.15, y: height * 0.12))
                wax.addQuadCurve(to: CGPoint(x: middle + width * 0.15, y: height * 0.12), control: CGPoint(x: middle, y: height * 0.0))
                wax.addLine(to: CGPoint(x: right, y: base))
                wax.closeSubpath()
                context.fill(wax, with: .color(color))
                shade(wax, across: barrel, in: context)
                // The paper wrapper's edge.
                let wrapper = Path(CGRect(x: left, y: base - height * 0.05, width: barrel.width, height: height * 0.05))
                context.fill(wrapper, with: .color(color))
                shade(wrapper, across: barrel, in: context)
                context.fill(Path(CGRect(x: left, y: base - height * 0.05, width: barrel.width, height: 0.8)), with: .color(.black.opacity(0.35)))

            case .watercolor:
                // A metal ferrule and a soft brush: wet, blending color.
                let ferrule = Path(CGRect(x: left + width * 0.05, y: height * 0.3, width: barrel.width - width * 0.1, height: base - height * 0.3))
                metal(ferrule, across: barrel, in: context)
                var brush = Path()
                brush.move(to: CGPoint(x: left + width * 0.05, y: height * 0.31))
                // Full in the middle, drawn to a point like a wet brush.
                brush.addCurve(to: top, control1: CGPoint(x: left - width * 0.03, y: height * 0.2), control2: CGPoint(x: middle - width * 0.05, y: height * 0.07))
                brush.addCurve(to: CGPoint(x: right - width * 0.05, y: height * 0.31), control1: CGPoint(x: middle + width * 0.05, y: height * 0.07), control2: CGPoint(x: right + width * 0.03, y: height * 0.2))
                brush.closeSubpath()
                context.fill(brush, with: .color(color))
                shade(brush, across: barrel, in: context)

            case .marker:
                // A round bullet tip: a bold, even line.
                let collar = taper(from: left, to: right, base: base, tipY: height * 0.3, tipWidth: width * 0.44, center: middle)
                glossyBlack(collar, across: barrel, in: context)
                let tip = Path(roundedRect: CGRect(x: middle - width * 0.18, y: height * 0.08, width: width * 0.36, height: height * 0.25),
                               cornerRadii: RectangleCornerRadii(topLeading: width * 0.18, bottomLeading: 0, bottomTrailing: 0, topTrailing: width * 0.18))
                context.fill(tip, with: .color(color))
                shade(tip, across: barrel, in: context)

            case .highlighter:
                // A wide chisel of see-through ink.
                let collar = taper(from: left, to: right, base: base, tipY: height * 0.26, tipWidth: barrel.width * 0.9, center: middle)
                glossyBlack(collar, across: barrel, in: context)
                var chisel = Path()
                chisel.move(to: CGPoint(x: left + width * 0.03, y: height * 0.27))
                chisel.addLine(to: CGPoint(x: left + width * 0.03, y: height * 0.12))
                chisel.addLine(to: CGPoint(x: right - width * 0.03, y: height * 0.02))
                chisel.addLine(to: CGPoint(x: right - width * 0.03, y: height * 0.27))
                chisel.closeSubpath()
                context.fill(chisel, with: .color(color.opacity(0.8)))
                shade(chisel, across: barrel, in: context)

            case .eraser, .text, .lasso, .laser:
                break
            }
        }
    }

    // MARK: Shapes

    /// A cone narrowing from the barrel's width to `tipWidth` at `tipY`.
    private func taper(from left: CGFloat, to right: CGFloat, base: CGFloat, tipY: CGFloat, tipWidth: CGFloat, center: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: left, y: base))
        path.addLine(to: CGPoint(x: center - tipWidth / 2, y: tipY))
        path.addLine(to: CGPoint(x: center + tipWidth / 2, y: tipY))
        path.addLine(to: CGPoint(x: right, y: base))
        path.closeSubpath()
        return path
    }

    private func nibShape(left: CGFloat, right: CGFloat, base: CGFloat, top: CGPoint, flare: CGFloat, height: CGFloat) -> Path {
        var nib = Path()
        nib.move(to: CGPoint(x: left, y: base))
        nib.addQuadCurve(to: top, control: CGPoint(x: left - flare, y: height * 0.24))
        nib.addQuadCurve(to: CGPoint(x: right, y: base), control: CGPoint(x: right + flare, y: height * 0.24))
        nib.closeSubpath()
        return nib
    }

    private func slit(from start: CGPoint, to end: CGPoint, hole: Bool, in context: GraphicsContext) {
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        context.stroke(line, with: .color(.black.opacity(0.55)), lineWidth: 0.8)
        if hole {
            context.fill(Path(ellipseIn: CGRect(x: end.x - 1.5, y: end.y - 0.5, width: 3, height: 3)), with: .color(.black.opacity(0.65)))
        }
    }

    /// The colored ring where a nib meets the barrel.
    private func ring(left: CGFloat, width: CGFloat, base: CGFloat, in context: GraphicsContext) {
        let ring = Path(CGRect(x: left, y: base - 2, width: width, height: 2.5))
        context.fill(ring, with: .color(color))
        shade(ring, across: CGRect(x: left, y: base - 2, width: width, height: 2.5), in: context)
    }

    private func triangle(_ top: CGPoint, width: CGFloat, height: CGFloat, baseY: CGFloat? = nil) -> Path {
        let bottom = baseY ?? top.y + height
        var path = Path()
        path.move(to: top)
        path.addLine(to: CGPoint(x: top.x - width / 2, y: bottom))
        path.addLine(to: CGPoint(x: top.x + width / 2, y: bottom))
        path.closeSubpath()
        return path
    }

    // MARK: Materials

    /// Glossy black plastic, lit from the left.
    private func glossyBlack(_ path: Path, across rect: CGRect, in context: GraphicsContext) {
        context.fill(path, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(white: 0.06), location: 0),
                .init(color: Color(white: 0.34), location: 0.26),
                .init(color: Color(white: 0.14), location: 0.5),
                .init(color: Color(white: 0.04), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
    }

    /// Lights a colored part like a cylinder: highlight on the left, shadow
    /// on the right edge. Works on any color.
    private func shade(_ path: Path, across rect: CGRect, in context: GraphicsContext) {
        context.fill(path, with: .linearGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.12), location: 0),
                .init(color: .white.opacity(0.5), location: 0.28),
                .init(color: .white.opacity(0.0), location: 0.55),
                .init(color: .black.opacity(0.3), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
    }

    /// Polished steel.
    private func metal(_ path: Path, across rect: CGRect, in context: GraphicsContext) {
        context.fill(path, with: .linearGradient(
            Gradient(colors: [Color(white: 0.5), Color(white: 0.95), Color(white: 0.74), Color(white: 0.42)]),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
    }

    /// Polished gold.
    private func gold(_ path: Path, across rect: CGRect, in context: GraphicsContext) {
        context.fill(path, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.60, green: 0.45, blue: 0.18), Color(red: 1.0, green: 0.88, blue: 0.55),
                Color(red: 0.80, green: 0.63, blue: 0.28), Color(red: 0.55, green: 0.40, blue: 0.15),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0),
            endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
    }
}
