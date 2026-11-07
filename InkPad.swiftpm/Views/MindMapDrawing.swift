import PencilKit
import SwiftUI

/// A puffy cloud around an idea.
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bumpsAcross = max(Int(rect.width / 34), 3)
        let bumpsDown = max(Int(rect.height / 30), 2)
        let inset = rect.insetBy(dx: 8, dy: 8)
        var points: [CGPoint] = []
        for index in 0..<bumpsAcross { points.append(CGPoint(x: inset.minX + inset.width * CGFloat(index) / CGFloat(bumpsAcross), y: inset.minY)) }
        for index in 0..<bumpsDown { points.append(CGPoint(x: inset.maxX, y: inset.minY + inset.height * CGFloat(index) / CGFloat(bumpsDown))) }
        for index in 0..<bumpsAcross { points.append(CGPoint(x: inset.maxX - inset.width * CGFloat(index) / CGFloat(bumpsAcross), y: inset.maxY)) }
        for index in 0..<bumpsDown { points.append(CGPoint(x: inset.minX, y: inset.maxY - inset.height * CGFloat(index) / CGFloat(bumpsDown))) }
        guard let first = points.first else { return path }
        path.move(to: first)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            let middle = CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2)
            // Push the control point outward for a bump.
            let dx = middle.x - center.x
            let dy = middle.y - center.y
            let length = max(sqrt(dx * dx + dy * dy), 1)
            let bulge: CGFloat = 16
            path.addQuadCurve(to: next, control: CGPoint(x: middle.x + dx / length * bulge, y: middle.y + dy / length * bulge))
        }
        path.closeSubpath()
        return path
    }
}

/// A leaf: pointed at both ends, round in the middle.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.55))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.55))
        path.closeSubpath()
        return path
    }
}

/// The background, outline and glow of an idea in a given shape.
struct MindNodeChrome: ViewModifier {
    let shape: MindMapStyle.NodeShape
    let color: Color
    let isRoot: Bool
    let isSelected: Bool
    let glows: Bool

    func body(content: Content) -> some View {
        let fill = isRoot ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.18))
        let outline = color.opacity(isSelected ? 1 : 0.6)
        let width: CGFloat = isSelected ? 3 : 1.5
        let glow = glows ? color.opacity(isSelected ? 0.9 : 0.4) : Color.clear
        let radius: CGFloat = isSelected ? 16 : 8
        switch shape {
        case .capsule:
            content
                .background(Capsule(style: .continuous).fill(fill))
                .overlay(Capsule(style: .continuous).stroke(outline, lineWidth: width))
                .shadow(color: glow, radius: radius)
        case .rounded:
            content
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(outline, lineWidth: width))
                .shadow(color: glow, radius: radius)
        case .box:
            content
                .background(Rectangle().fill(fill))
                .overlay(Rectangle().stroke(outline, lineWidth: width))
                .shadow(color: glow, radius: radius)
        case .circle:
            // A circle big enough for the text inside it.
            content
                .padding(6)
                .frame(minWidth: 64, minHeight: 64)
                .background {
                    GeometryReader { geometry in
                        let side = max(geometry.size.width, geometry.size.height)
                        Circle()
                            .fill(fill)
                            .overlay(Circle().stroke(outline, lineWidth: width))
                            .frame(width: side, height: side)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
                .shadow(color: glow, radius: radius)
        case .cloud:
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(CloudShape().fill(fill))
                .overlay(CloudShape().stroke(outline, lineWidth: width))
                .shadow(color: glow, radius: radius)
        case .leaf:
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(LeafShape().fill(isRoot ? fill : AnyShapeStyle(color.opacity(0.3))))
                .overlay(LeafShape().stroke(outline, lineWidth: width))
                .shadow(color: glow, radius: radius)
        case .underline:
            content
                .overlay(alignment: .bottom) {
                    Capsule().fill(color).frame(height: isSelected ? 4 : 3).offset(y: 2)
                }
                .background(isRoot ? AnyShapeStyle(color.opacity(0.2)) : AnyShapeStyle(Color.clear), in: Capsule())
                .shadow(color: glow, radius: radius / 2)
        case .plain:
            content
                .background(isSelected ? AnyShapeStyle(color.opacity(0.15)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

enum MindBranchPainter {
    /// Draws a branch from a parent to a child in the map's style.
    /// `weight` (0...1) is how much of the map hangs from the child.
    static func draw(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint, style: MindMapStyle, color: Color, scale: CGFloat, weight: CGFloat, glows: Bool) {
        switch style.branch {
        case .curved:
            let path = curve(from: start, to: end, layout: style.layout)
            if glows { context.stroke(path, with: .color(color.opacity(0.25)), lineWidth: 8 * scale) }
            context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 2.5 * scale)
        case .straight:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            if glows { context.stroke(path, with: .color(color.opacity(0.2)), lineWidth: 7 * scale) }
            context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 2 * scale)
        case .elbow:
            var path = Path()
            path.move(to: start)
            if style.layout == .orgChart || style.layout == .tree {
                let midY = (start.y + end.y) / 2
                path.addLine(to: CGPoint(x: start.x, y: midY))
                path.addLine(to: CGPoint(x: end.x, y: midY))
            } else {
                let midX = (start.x + end.x) / 2
                path.addLine(to: CGPoint(x: midX, y: start.y))
                path.addLine(to: CGPoint(x: midX, y: end.y))
            }
            path.addLine(to: end)
            if glows { context.stroke(path, with: .color(color.opacity(0.2)), lineWidth: 7 * scale) }
            context.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
        case .organic:
            let thick = (4 + 14 * weight) * scale
            let thin = (1.5 + 3 * weight) * scale
            let path = tapered(from: start, to: end, startWidth: thick, endWidth: thin, layout: style.layout)
            if glows { context.fill(path, with: .color(color.opacity(0.2))) ; context.stroke(path, with: .color(color.opacity(0.15)), lineWidth: 6 * scale) }
            context.fill(path, with: .color(color.opacity(0.9)))
        case .wood:
            let bark = Color(red: 0.45, green: 0.3, blue: 0.17)
            let thick = (5 + 20 * weight) * scale
            let thin = (2 + 5 * weight) * scale
            let path = tapered(from: start, to: end, startWidth: thick, endWidth: thin, layout: .tree)
            context.fill(path, with: .linearGradient(Gradient(colors: [bark, Color(red: 0.6, green: 0.42, blue: 0.25)]), startPoint: start, endPoint: end))
            // A thin line of light along the bark.
            context.stroke(curve(from: start, to: end, layout: .tree), with: .color(.white.opacity(0.12)), lineWidth: max(thin * 0.4, 1))
        }
    }

    /// The trunk and a patch of ground under a tree's central idea.
    static func drawTrunk(in context: inout GraphicsContext, at root: CGPoint, scale: CGFloat, wood: Bool, color: Color) {
        let ground = CGPoint(x: root.x, y: root.y + 170 * scale)
        var trunk = Path()
        let top = 16 * scale
        let bottom = 34 * scale
        trunk.move(to: CGPoint(x: root.x - top, y: root.y))
        trunk.addQuadCurve(to: CGPoint(x: ground.x - bottom, y: ground.y), control: CGPoint(x: root.x - top * 0.6, y: (root.y + ground.y) / 2))
        // Roots flare out at the bottom.
        trunk.addQuadCurve(to: CGPoint(x: ground.x - bottom * 1.8, y: ground.y + 8 * scale), control: CGPoint(x: ground.x - bottom * 1.1, y: ground.y + 2 * scale))
        trunk.addLine(to: CGPoint(x: ground.x + bottom * 1.8, y: ground.y + 8 * scale))
        trunk.addQuadCurve(to: CGPoint(x: ground.x + bottom, y: ground.y), control: CGPoint(x: ground.x + bottom * 1.1, y: ground.y + 2 * scale))
        trunk.addQuadCurve(to: CGPoint(x: root.x + top, y: root.y), control: CGPoint(x: root.x + top * 0.6, y: (root.y + ground.y) / 2))
        trunk.closeSubpath()
        let bark = wood ? Color(red: 0.45, green: 0.3, blue: 0.17) : color.opacity(0.8)
        context.fill(trunk, with: .linearGradient(Gradient(colors: [bark.opacity(0.9), bark]), startPoint: root, endPoint: ground))
        let groundRect = CGRect(x: ground.x - 160 * scale, y: ground.y - 4 * scale, width: 320 * scale, height: 26 * scale)
        context.fill(Path(ellipseIn: groundRect), with: .radialGradient(Gradient(colors: [Color.green.opacity(0.45), Color.green.opacity(0)]), center: CGPoint(x: groundRect.midX, y: groundRect.midY), startRadius: 0, endRadius: 160 * scale))
    }

    private static func controls(from start: CGPoint, to end: CGPoint, layout: MindMapStyle.Layout) -> (CGPoint, CGPoint) {
        switch layout {
        case .orgChart:
            let bend = (end.y - start.y) * 0.5
            return (CGPoint(x: start.x, y: start.y + bend), CGPoint(x: end.x, y: end.y - bend))
        case .tree:
            // Branches rise first, then lean out.
            return (CGPoint(x: start.x, y: start.y + (end.y - start.y) * 0.6), CGPoint(x: end.x - (end.x - start.x) * 0.25, y: end.y))
        case .radial:
            return (CGPoint(x: start.x + (end.x - start.x) * 0.4, y: start.y + (end.y - start.y) * 0.1),
                    CGPoint(x: end.x - (end.x - start.x) * 0.1, y: end.y - (end.y - start.y) * 0.4))
        default:
            let bend = (end.x - start.x) * 0.5
            return (CGPoint(x: start.x + bend, y: start.y), CGPoint(x: end.x - bend, y: end.y))
        }
    }

    static func curve(from start: CGPoint, to end: CGPoint, layout: MindMapStyle.Layout) -> Path {
        let (c1, c2) = controls(from: start, to: end, layout: layout)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)
        return path
    }

    /// A curve that is thick at the start and thin at the end.
    static func tapered(from start: CGPoint, to end: CGPoint, startWidth: CGFloat, endWidth: CGFloat, layout: MindMapStyle.Layout) -> Path {
        let (c1, c2) = controls(from: start, to: end, layout: layout)
        let steps = 24
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let x = u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x
            let y = u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
            return CGPoint(x: x, y: y)
        }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let here = point(t)
            let ahead = point(min(t + 0.01, 1))
            let behind = point(max(t - 0.01, 0))
            var dx = ahead.x - behind.x
            var dy = ahead.y - behind.y
            let length = max(sqrt(dx * dx + dy * dy), 0.0001)
            dx /= length
            dy /= length
            let half = (startWidth + (endWidth - startWidth) * t) / 2
            left.append(CGPoint(x: here.x - dy * half, y: here.y + dx * half))
            right.append(CGPoint(x: here.x + dy * half, y: here.y - dx * half))
        }
        var path = Path()
        path.move(to: left[0])
        left.dropFirst().forEach { path.addLine(to: $0) }
        right.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

/// Handwriting on an idea, drawn from its saved PencilKit data.
struct InkImage: View {
    let data: Data
    let color: Color
    var maxHeight: CGFloat = 60
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = Self.render(data, dark: colorScheme == .dark) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: maxHeight)
        } else {
            Image(systemName: "scribble")
                .foregroundStyle(color)
        }
    }

    private static func render(_ data: Data, dark: Bool) -> UIImage? {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 2)
        }
        return image
    }
}
