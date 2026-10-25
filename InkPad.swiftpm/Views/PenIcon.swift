import SwiftUI

/// An upright pen drawn in the style of Apple Notes' tool picker: a dark
/// barrel with a color band, and a tip shaped like the real tool and colored
/// with its ink.
struct PenIcon: View {
    let tool: DrawingTool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let barrel = CGRect(x: width * 0.22, y: height * 0.42, width: width * 0.56, height: height * 0.58)
            let barrelColor = Color(white: 0.18)

            // Barrel and color band.
            context.fill(Path(roundedRect: barrel, cornerRadius: 2), with: .color(barrelColor))
            context.fill(
                Path(CGRect(x: barrel.minX, y: barrel.minY + height * 0.16, width: barrel.width, height: height * 0.07)),
                with: .color(color)
            )

            // Tip.
            let top = CGPoint(x: width / 2, y: height * 0.02)
            let left = barrel.minX
            let right = barrel.maxX
            let base = barrel.minY
            switch tool {
            case .pen, .monoline:
                var cone = Path()
                cone.move(to: CGPoint(x: left, y: base))
                cone.addLine(to: CGPoint(x: width / 2 - 1.5, y: height * 0.08))
                cone.addLine(to: CGPoint(x: width / 2 + 1.5, y: height * 0.08))
                cone.addLine(to: CGPoint(x: right, y: base))
                cone.closeSubpath()
                context.fill(cone, with: .color(Color(white: 0.28)))
                let pointHeight = tool == .monoline ? 0.12 : 0.16
                context.fill(triangle(top, width: width * 0.14, height: height * pointHeight), with: .color(color))

            case .pencil:
                var wood = Path()
                wood.move(to: CGPoint(x: left, y: base))
                wood.addLine(to: top)
                wood.addLine(to: CGPoint(x: right, y: base))
                wood.closeSubpath()
                context.fill(wood, with: .color(Color(red: 0.93, green: 0.80, blue: 0.62)))
                context.fill(triangle(top, width: width * 0.2, height: height * 0.14), with: .color(color))

            case .fountainPen, .quill:
                // A metal nib with a slit and breather hole.
                var nib = Path()
                nib.move(to: CGPoint(x: left, y: base))
                nib.addQuadCurve(to: top, control: CGPoint(x: left - width * 0.08, y: height * 0.18))
                nib.addQuadCurve(to: CGPoint(x: right, y: base), control: CGPoint(x: right + width * 0.08, y: height * 0.18))
                nib.closeSubpath()
                let metal = tool == .quill ? Color(red: 0.80, green: 0.66, blue: 0.36) : Color(white: 0.78)
                context.fill(nib, with: .color(metal))
                var slit = Path()
                slit.move(to: top)
                slit.addLine(to: CGPoint(x: width / 2, y: height * 0.26))
                context.stroke(slit, with: .color(.black.opacity(0.6)), lineWidth: 0.8)
                context.fill(Path(ellipseIn: CGRect(x: width / 2 - 1.5, y: height * 0.26, width: 3, height: 3)), with: .color(.black.opacity(0.7)))
                context.fill(Path(CGRect(x: left, y: base - 2, width: barrel.width, height: 2)), with: .color(color))

            case .marker, .highlighter:
                // A chisel tip.
                var collar = Path()
                collar.move(to: CGPoint(x: left, y: base))
                collar.addLine(to: CGPoint(x: left + width * 0.06, y: height * 0.24))
                collar.addLine(to: CGPoint(x: right - width * 0.06, y: height * 0.24))
                collar.addLine(to: CGPoint(x: right, y: base))
                collar.closeSubpath()
                context.fill(collar, with: .color(Color(white: 0.3)))
                var chisel = Path()
                chisel.move(to: CGPoint(x: left + width * 0.1, y: height * 0.24))
                chisel.addLine(to: CGPoint(x: left + width * 0.1, y: height * 0.1))
                chisel.addLine(to: CGPoint(x: right - width * 0.1, y: height * 0.02))
                chisel.addLine(to: CGPoint(x: right - width * 0.1, y: height * 0.24))
                chisel.closeSubpath()
                context.fill(chisel, with: .color(tool == .highlighter ? color.opacity(0.75) : color))

            case .crayon:
                var crayon = Path()
                crayon.move(to: CGPoint(x: left, y: base))
                crayon.addLine(to: CGPoint(x: left + width * 0.08, y: height * 0.14))
                crayon.addQuadCurve(to: CGPoint(x: right - width * 0.08, y: height * 0.14), control: CGPoint(x: width / 2, y: 0))
                crayon.addLine(to: CGPoint(x: right, y: base))
                crayon.closeSubpath()
                context.fill(crayon, with: .color(color))

            case .watercolor:
                var ferrule = Path(CGRect(x: left + width * 0.04, y: height * 0.3, width: barrel.width - width * 0.08, height: base - height * 0.3))
                ferrule.closeSubpath()
                context.fill(ferrule, with: .color(Color(white: 0.7)))
                var brush = Path()
                brush.move(to: CGPoint(x: left + width * 0.04, y: height * 0.3))
                brush.addQuadCurve(to: top, control: CGPoint(x: left, y: height * 0.1))
                brush.addQuadCurve(to: CGPoint(x: right - width * 0.04, y: height * 0.3), control: CGPoint(x: right, y: height * 0.1))
                brush.closeSubpath()
                context.fill(brush, with: .color(color))

            case .eraser, .text, .lasso, .laser:
                break
            }
        }
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
