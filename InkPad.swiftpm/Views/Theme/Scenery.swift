import SwiftUI

/// Nature for the season themes: grass, flowers, leaves or snow drawn at
/// the edges of a screen, with petals, leaves or snow falling softly.
enum Season: String, Codable, CaseIterable, Identifiable {
    case none, spring, summer, autumn, winter

    var id: Self { self }

    var title: String { self == .none ? "None" : rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .none: "circle.slash"
        case .spring: "camera.macro"
        case .summer: "sun.max.fill"
        case .autumn: "leaf.fill"
        case .winter: "snowflake"
        }
    }

    /// Colors of the falling things and the ground.
    fileprivate var particleColors: [Color] {
        switch self {
        case .none: []
        case .spring: [Color(red: 1, green: 0.72, blue: 0.82), Color(red: 1, green: 0.85, blue: 0.9), .white, Color(red: 0.98, green: 0.6, blue: 0.75)]
        case .summer: [Color(red: 1, green: 0.9, blue: 0.4), Color(red: 1, green: 0.8, blue: 0.3), .white]
        case .autumn: [Color(red: 0.93, green: 0.6, blue: 0.1), Color(red: 0.85, green: 0.35, blue: 0.1), Color(red: 0.95, green: 0.78, blue: 0.2), Color(red: 0.6, green: 0.3, blue: 0.12)]
        case .winter: [.white, Color(red: 0.88, green: 0.94, blue: 1)]
        }
    }
}

struct SceneryView: View {
    let season: Season
    var animated = true
    var isSidebar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                canvas(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: nil)
        }
    }

    private func canvas(time: TimeInterval?) -> some View {
        Canvas { context, size in
            let painter = SceneryPainter(season: season, size: size, isDark: colorScheme == .dark, isSidebar: isSidebar)
            painter.drawGround(in: &context)
            painter.drawParticles(in: &context, time: time)
        }
    }
}

/// Repeatable "random" numbers, so the scenery looks the same every time.
private func noise(_ seed: Double) -> Double {
    let value = sin(seed * 12.9898 + 78.233) * 43_758.5453
    return value - floor(value)
}

private struct SceneryPainter {
    let season: Season
    let size: CGSize
    let isDark: Bool
    let isSidebar: Bool

    private var scale: CGFloat { isSidebar ? 0.6 : 1 }

    // MARK: Ground

    func drawGround(in context: inout GraphicsContext) {
        switch season {
        case .none: break
        case .spring:
            drawGrass(in: &context, height: 46, colors: [Color(red: 0.36, green: 0.7, blue: 0.3), Color(red: 0.5, green: 0.8, blue: 0.35), Color(red: 0.28, green: 0.58, blue: 0.25)])
            drawFlowers(in: &context)
            if !isSidebar { drawBranch(in: &context, leafColors: [Color(red: 0.55, green: 0.8, blue: 0.4), Color(red: 1, green: 0.75, blue: 0.85)]) }
        case .summer:
            drawSun(in: &context)
            drawGrass(in: &context, height: 60, colors: [Color(red: 0.6, green: 0.75, blue: 0.25), Color(red: 0.75, green: 0.8, blue: 0.3), Color(red: 0.45, green: 0.65, blue: 0.2)])
        case .autumn:
            if !isSidebar { drawBranch(in: &context, leafColors: season.particleColors) }
            drawLeafPile(in: &context)
        case .winter:
            drawFrost(in: &context)
            drawSnowDrift(in: &context)
        }
    }

    private func drawGrass(in context: inout GraphicsContext, height: CGFloat, colors: [Color]) {
        let count = Int(size.width / (6 * scale))
        let opacity = isDark ? 0.55 : 0.8
        for index in 0..<max(count, 1) {
            let seed = Double(index)
            let x = CGFloat(index) * 6 * scale + CGFloat(noise(seed) * 4)
            let tall = height * scale * CGFloat(0.4 + noise(seed + 0.3) * 0.6)
            let lean = CGFloat(noise(seed + 0.7) - 0.5) * 14 * scale
            var blade = Path()
            blade.move(to: CGPoint(x: x - 3 * scale, y: size.height))
            blade.addQuadCurve(to: CGPoint(x: x + lean, y: size.height - tall), control: CGPoint(x: x - 1, y: size.height - tall * 0.5))
            blade.addQuadCurve(to: CGPoint(x: x + 3 * scale, y: size.height), control: CGPoint(x: x + 1, y: size.height - tall * 0.5))
            context.fill(blade, with: .color(colors[index % colors.count].opacity(opacity)))
        }
    }

    private func drawFlowers(in context: inout GraphicsContext) {
        let count = Int(size.width / (70 * scale))
        let petals: [Color] = [.white, Color(red: 1, green: 0.7, blue: 0.8), Color(red: 1, green: 0.85, blue: 0.35), Color(red: 0.75, green: 0.6, blue: 1)]
        for index in 0..<count {
            let seed = Double(index) + 100
            let center = CGPoint(
                x: CGFloat(noise(seed)) * size.width,
                y: size.height - (18 + CGFloat(noise(seed + 0.4)) * 26) * scale
            )
            let radius = (4 + CGFloat(noise(seed + 0.9)) * 3) * scale
            for petal in 0..<5 {
                let angle = Double(petal) / 5 * 2 * .pi
                let spot = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                context.fill(Path(ellipseIn: CGRect(x: spot.x - radius * 0.7, y: spot.y - radius * 0.7, width: radius * 1.4, height: radius * 1.4)),
                             with: .color(petals[index % petals.count].opacity(0.9)))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.55, y: center.y - radius * 0.55, width: radius * 1.1, height: radius * 1.1)),
                         with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
        }
    }

    private func drawSun(in context: inout GraphicsContext) {
        let center = CGPoint(x: size.width - 60 * scale, y: 50 * scale)
        let glow = Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.4).opacity(isDark ? 0.35 : 0.6), .clear])
        let radius = 220 * scale
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(glow, center: center, startRadius: 0, endRadius: radius)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 26 * scale, y: center.y - 26 * scale, width: 52 * scale, height: 52 * scale)),
            with: .color(Color(red: 1, green: 0.82, blue: 0.3).opacity(isDark ? 0.5 : 0.85))
        )
    }

    /// A branch reaching in from the top corner, with leaves.
    private func drawBranch(in context: inout GraphicsContext, leafColors: [Color]) {
        // From the top right corner, away from titles on the left.
        let start = CGPoint(x: size.width + 10, y: 24)
        let end = CGPoint(x: size.width - min(size.width * 0.3, 240), y: 64)
        var branch = Path()
        branch.move(to: start)
        branch.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: 6))
        context.stroke(branch, with: .color(Color(red: 0.42, green: 0.27, blue: 0.15).opacity(isDark ? 0.6 : 0.8)),
                       style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round))
        let leaves = 11
        for index in 0..<leaves {
            let fraction = CGFloat(index + 1) / CGFloat(leaves + 1)
            let x = start.x + (end.x - start.x) * fraction
            // On the curve, roughly.
            let t = fraction
            let y = (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * 6 + t * t * end.y
            let side: Double = index.isMultiple(of: 2) ? 1 : -1
            let angle = Angle.degrees(side * (40 + noise(Double(index) + 7) * 30) + 90)
            drawLeaf(in: &context, at: CGPoint(x: x, y: y + CGFloat(side) * 4), length: (18 + CGFloat(noise(Double(index))) * 8) * scale,
                     angle: angle, color: leafColors[index % leafColors.count])
        }
    }

    private func drawLeafPile(in context: inout GraphicsContext) {
        let count = Int(size.width / (14 * scale))
        for index in 0..<count {
            let seed = Double(index) + 300
            let x = CGFloat(noise(seed)) * size.width
            // Leaves gather in the corners.
            let edge = min(x, size.width - x) / max(size.width / 2, 1)
            let pile = (1 - edge) * 40 * scale + 8
            let y = size.height - CGFloat(noise(seed + 0.5)) * pile
            drawLeaf(in: &context, at: CGPoint(x: x, y: y), length: (14 + CGFloat(noise(seed + 0.2)) * 10) * scale,
                     angle: .degrees(noise(seed + 0.8) * 360), color: season.particleColors[index % season.particleColors.count])
        }
    }

    private func drawFrost(in context: inout GraphicsContext) {
        let frost = Gradient(colors: [.white.opacity(isDark ? 0.12 : 0.55), .clear])
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 90 * scale)),
                     with: .linearGradient(frost, startPoint: .zero, endPoint: CGPoint(x: 0, y: 90 * scale)))
    }

    private func drawSnowDrift(in context: inout GraphicsContext) {
        var drift = Path()
        drift.move(to: CGPoint(x: 0, y: size.height))
        let waves = 5
        var x: CGFloat = 0
        let step = size.width / CGFloat(waves)
        drift.addLine(to: CGPoint(x: 0, y: size.height - 30 * scale))
        for index in 0..<waves {
            let peak = (20 + CGFloat(noise(Double(index) + 50)) * 26) * scale
            drift.addQuadCurve(
                to: CGPoint(x: x + step, y: size.height - 24 * scale),
                control: CGPoint(x: x + step / 2, y: size.height - 24 * scale - peak)
            )
            x += step
        }
        drift.addLine(to: CGPoint(x: size.width, y: size.height))
        drift.closeSubpath()
        context.fill(drift, with: .color(.white.opacity(isDark ? 0.3 : 0.9)))
        context.stroke(drift, with: .color(Color(red: 0.75, green: 0.85, blue: 0.95).opacity(0.6)), lineWidth: 1)
    }

    // MARK: Falling things

    func drawParticles(in context: inout GraphicsContext, time: TimeInterval?) {
        guard season != .none else { return }
        let count = isSidebar ? 6 : 22
        let colors = season.particleColors
        let height = size.height + 60
        for index in 0..<count {
            let seed = Double(index) + 500
            // Without time (no animation) the particles rest where they are.
            let t = time ?? noise(seed + 3) * 40
            let speed = (season == .winter ? 18 : 26) + noise(seed + 0.1) * 22
            let rising = season == .summer
            var y = (noise(seed + 0.2) * height + speed * t).truncatingRemainder(dividingBy: height) - 30
            if rising { y = height - y - 60 }
            let sway = sin(t * (0.6 + noise(seed + 0.4)) + noise(seed) * 6) * (14 + noise(seed + 0.5) * 20)
            let x = noise(seed + 0.6) * Double(size.width) + sway
            let point = CGPoint(x: x, y: y)
            let color = colors[index % colors.count]
            let spin = Angle.degrees(t * (40 + noise(seed + 0.7) * 80) + noise(seed) * 360)
            let length = CGFloat(10 + noise(seed + 0.8) * 10) * scale

            switch season {
            case .none:
                break
            case .spring:
                drawPetal(in: &context, at: point, length: length * 0.8, angle: spin, color: color)
            case .summer:
                let glow = Gradient(colors: [color.opacity(0.9), color.opacity(0)])
                let radius = length * 0.6
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .radialGradient(glow, center: point, startRadius: 0, endRadius: radius))
            case .autumn:
                drawLeaf(in: &context, at: point, length: length * 1.3, angle: spin, color: color)
            case .winter:
                let radius = length * 0.3
                let flake = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                context.fill(flake, with: .color(color.opacity(isDark ? 0.8 : 0.95)))
                if !isDark {
                    context.stroke(flake, with: .color(Color(red: 0.55, green: 0.7, blue: 0.88).opacity(0.5)), lineWidth: 0.8)
                }
                if index.isMultiple(of: 4) {
                    context.draw(Text(Image(systemName: "snowflake")).font(.system(size: length)).foregroundStyle(Color(red: 0.7, green: 0.82, blue: 0.95)), at: point)
                }
            }
        }
    }

    // MARK: Shapes

    private func drawLeaf(in context: inout GraphicsContext, at point: CGPoint, length: CGFloat, angle: Angle, color: Color) {
        var leaf = Path()
        leaf.move(to: CGPoint(x: 0, y: -length / 2))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: length / 2), control: CGPoint(x: length * 0.45, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -length / 2), control: CGPoint(x: -length * 0.45, y: 0))
        var vein = Path()
        vein.move(to: CGPoint(x: 0, y: -length / 2))
        vein.addLine(to: CGPoint(x: 0, y: length / 2 + length * 0.15))
        let transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: angle.radians)
        context.fill(leaf.applying(transform), with: .color(color.opacity(isDark ? 0.7 : 0.9)))
        context.stroke(vein.applying(transform), with: .color(.black.opacity(0.15)), lineWidth: 0.8)
    }

    private func drawPetal(in context: inout GraphicsContext, at point: CGPoint, length: CGFloat, angle: Angle, color: Color) {
        let petal = Path(ellipseIn: CGRect(x: -length / 2, y: -length / 4, width: length, height: length / 2))
        let transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: angle.radians)
        context.fill(petal.applying(transform), with: .color(color.opacity(0.85)))
    }
}
