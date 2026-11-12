import SwiftUI

// MARK: Species

/// The kinds of plant a subject can grow into.
enum PlantSpecies: String, CaseIterable, Identifiable, Codable {
    case oak, pine, cherry, palm, cactus, sunflower, bonsai

    var id: Self { self }

    var title: String {
        switch self {
        case .oak: "Oak"
        case .pine: "Pine"
        case .cherry: "Cherry Blossom"
        case .palm: "Palm"
        case .cactus: "Cactus"
        case .sunflower: "Sunflower"
        case .bonsai: "Bonsai"
        }
    }

    var systemImage: String {
        switch self {
        case .oak: "tree.fill"
        case .pine: "arrowtriangle.up.fill"
        case .cherry: "camera.macro"
        case .palm: "beach.umbrella.fill"
        case .cactus: "staroflife.fill"
        case .sunflower: "sun.max.fill"
        case .bonsai: "leaf.fill"
        }
    }

    /// Picked from the subject's name, so it stays the same.
    static func automatic(for subject: String) -> PlantSpecies {
        let cases: [PlantSpecies] = PlantSpecies.allCases
        let index = Int(GardenSeed.of(subject) % UInt64(cases.count))
        return cases[index]
    }
}

/// A stable number from a name (FNV-1a), so a plant always grows the same shape.
enum GardenSeed {
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}

/// Repeatable random numbers (SplitMix64).
struct GardenRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// 0...1.
    mutating func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    mutating func range(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * next()
    }
}

// MARK: Settings

/// Focus Garden choices, in UserDefaults (and synced).
@MainActor
final class GardenSettings: ObservableObject {
    static let shared = GardenSettings()

    struct Saved: Codable {
        /// One garden scene (else cards).
        var scene = true
        var wind = true
        /// Sky follows the time of day.
        var sky = true
        /// Plants grow before your eyes after a session.
        var celebrate = true
        var species: [String: PlantSpecies] = [:]
        /// Minutes each subject's plant had when last seen.
        var seen: [String: Int] = [:]

        init() {}

        enum CodingKeys: String, CodingKey { case scene, wind, sky, celebrate, species, seen }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scene = container.value(.scene, or: true)
            wind = container.value(.wind, or: true)
            sky = container.value(.sky, or: true)
            celebrate = container.value(.celebrate, or: true)
            species = container.value(.species, or: [:])
            seen = container.value(.seen, or: [:])
        }
    }

    private static let key = "gardenSettings"

    @Published var saved: Saved {
        didSet {
            if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let value = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = value
        } else {
            saved = Saved()
        }
    }

    func species(for subject: String) -> PlantSpecies {
        saved.species[subject] ?? PlantSpecies.automatic(for: subject)
    }

    func setSpecies(_ species: PlantSpecies?, for subject: String) {
        saved.species[subject] = species
    }
}

// MARK: Drawing

/// Draws each species from a seed to fully grown, dressed for the season.
enum TreePainter {
    private static let bark = Color(red: 0.4, green: 0.27, blue: 0.16)
    private static let soil = Color(red: 0.42, green: 0.29, blue: 0.19)

    static func draw(_ species: PlantSpecies, in context: GraphicsContext, size: CGSize, growth: Double, season: Season, seed: UInt64, ground: Bool) {
        let base = CGPoint(x: size.width / 2, y: size.height - (ground ? 12 : 4))
        if ground && species != .bonsai {
            let mound = Path(ellipseIn: CGRect(x: size.width * 0.22, y: base.y - 7, width: size.width * 0.56, height: 18))
            context.fill(mound, with: .color(soil))
        }
        // Seeds and sprouts are drawn larger in a big frame, so they show.
        let early: CGFloat = max(size.height / 170, 1)
        if growth < 0.08 && species != .bonsai {
            var scaled = context
            scaled.translateBy(x: base.x, y: base.y)
            scaled.scaleBy(x: early, y: early)
            drawSeed(in: scaled, at: .zero, growth: growth)
            return
        }
        if growth < 0.18 && species != .bonsai {
            var scaled = context
            scaled.translateBy(x: base.x, y: base.y)
            scaled.scaleBy(x: early, y: early)
            drawSprout(in: scaled, at: .zero, growth: growth, season: season)
            return
        }
        // 0...1 across the real growing.
        let t: Double = species == .bonsai ? growth : (growth - 0.18) / 0.82
        var random = GardenRandom(seed: seed)
        switch species {
        case .oak:
            drawBranchingTree(in: context, size: size, base: base, t: t, season: season, random: &random, cherry: false)
        case .cherry:
            drawBranchingTree(in: context, size: size, base: base, t: t, season: season, random: &random, cherry: true)
        case .pine:
            drawPine(in: context, size: size, base: base, t: t, season: season, random: &random)
        case .palm:
            drawPalm(in: context, size: size, base: base, t: t, season: season, random: &random)
        case .cactus:
            drawCactus(in: context, size: size, base: base, t: t, season: season)
        case .sunflower:
            drawSunflower(in: context, size: size, base: base, t: t, season: season)
        case .bonsai:
            drawBonsai(in: context, size: size, base: base, t: t, season: season, random: &random)
        }
    }

    static func groundColor(_ season: Season) -> Color {
        switch season {
        case .winter: Color(red: 0.93, green: 0.95, blue: 0.98)
        case .autumn: Color(red: 0.55, green: 0.45, blue: 0.25)
        default: Color(red: 0.36, green: 0.6, blue: 0.3)
        }
    }

    // MARK: First stages

    private static func drawSeed(in context: GraphicsContext, at base: CGPoint, growth: Double) {
        let seed = Path(ellipseIn: CGRect(x: base.x - 6, y: base.y - 10, width: 12, height: 8))
        context.fill(seed, with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)))
        if growth > 0.03 {
            var crack = Path()
            crack.move(to: CGPoint(x: base.x, y: base.y - 10))
            crack.addLine(to: CGPoint(x: base.x + 2, y: base.y - 15))
            context.stroke(crack, with: .color(Color(red: 0.4, green: 0.7, blue: 0.3)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private static func drawSprout(in context: GraphicsContext, at base: CGPoint, growth: Double, season: Season) {
        let height: CGFloat = CGFloat(14 + (growth - 0.08) * 260)
        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: CGPoint(x: base.x + 2, y: base.y - height), control: CGPoint(x: base.x - 6, y: base.y - height / 2))
        let green = Color(red: 0.38, green: 0.68, blue: 0.3)
        context.stroke(stem, with: .color(green), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let top = CGPoint(x: base.x + 2, y: base.y - height)
        let leafSize: CGFloat = CGFloat(8 + (growth - 0.08) * 80)
        for side in [-1.0, 1.0] {
            var leaf = context
            leaf.translateBy(x: top.x, y: top.y)
            leaf.rotate(by: .radians(side * 0.5))
            let rect = CGRect(x: side < 0 ? -leafSize : 0, y: -leafSize * 0.3, width: leafSize, height: leafSize * 0.55)
            leaf.fill(Path(ellipseIn: rect), with: .color(green.opacity(0.95)))
        }
    }

    // MARK: Oak and cherry

    private struct Twig {
        let from: CGPoint
        let to: CGPoint
        let control: CGPoint
        let width: CGFloat
    }

    private static func drawBranchingTree(in context: GraphicsContext, size: CGSize, base: CGPoint, t: Double, season: Season, random: inout GardenRandom, cherry: Bool) {
        let depth: Int = 1 + Int(t * 5.5)
        let trunk: Double = Double(size.height) * (0.12 + 0.1 * t)
        let width: Double = 3 + 12 * t
        var twigs: [Twig] = []
        var tips: [CGPoint] = []
        let spread: Double = cherry ? 0.56 : 0.46
        grow(from: base, angle: -Double.pi / 2, length: trunk, width: width, depth: depth, spread: spread, random: &random, twigs: &twigs, tips: &tips)
        for twig in twigs {
            var path = Path()
            path.move(to: twig.from)
            path.addQuadCurve(to: twig.to, control: twig.control)
            context.stroke(path, with: .color(bark), style: StrokeStyle(lineWidth: twig.width, lineCap: .round))
            if season == .winter && twig.width > 1.5 {
                var snow = Path()
                snow.move(to: CGPoint(x: twig.from.x, y: twig.from.y - twig.width * 0.45))
                snow.addQuadCurve(to: CGPoint(x: twig.to.x, y: twig.to.y - twig.width * 0.45), control: twig.control)
                context.stroke(snow, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(twig.width * 0.35, 1), lineCap: .round))
            }
        }
        let colors: [Color] = foliage(season: season, cherry: cherry)
        guard !colors.isEmpty else { return }
        let clump: Double = (cherry ? 8 : 10) + 10 * t
        for (index, tip) in tips.enumerated() {
            let blobs: Int = 3
            for blob in 0..<blobs {
                let dx: Double = random.range(-clump * 0.7, clump * 0.7)
                let dy: Double = random.range(-clump * 0.6, clump * 0.4)
                let r: Double = clump * random.range(0.55, 1)
                let rect = CGRect(x: Double(tip.x) + dx - r, y: Double(tip.y) + dy - r, width: r * 2, height: r * 1.8)
                let color: Color = colors[(index + blob) % colors.count]
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.88)))
            }
        }
        // Blossoms in spring (and on the cherry most of the year).
        let blooms: Bool = season == .spring || (cherry && season != .winter && season != .autumn)
        if blooms && t > 0.3 {
            let petal: Color = cherry ? Color(red: 1, green: 0.78, blue: 0.86) : .white
            for tip in tips where random.next() < 0.7 {
                let dx: Double = random.range(-clump * 0.6, clump * 0.6)
                let dy: Double = random.range(-clump * 0.6, clump * 0.3)
                let r: Double = 2.4 + 2 * t
                context.fill(Path(ellipseIn: CGRect(x: Double(tip.x) + dx - r, y: Double(tip.y) + dy - r, width: r * 2, height: r * 2)), with: .color(petal))
            }
        }
    }

    private static func grow(from point: CGPoint, angle: Double, length: Double, width: Double, depth: Int, spread: Double, random: inout GardenRandom, twigs: inout [Twig], tips: inout [CGPoint]) {
        let end = CGPoint(x: Double(point.x) + Math.cosine(angle) * length, y: Double(point.y) + Math.sine(angle) * length)
        let bend: Double = random.range(-0.25, 0.25)
        let middle = CGPoint(
            x: Double(point.x) + Math.cosine(angle + bend) * length * 0.55,
            y: Double(point.y) + Math.sine(angle + bend) * length * 0.55
        )
        twigs.append(Twig(from: point, to: end, control: middle, width: CGFloat(width)))
        guard depth > 0, length > 4 else {
            tips.append(end)
            return
        }
        let children: Int = random.next() < 0.25 ? 3 : 2
        for index in 0..<children {
            let side: Double = children == 2 ? (index == 0 ? -1 : 1) : Double(index - 1)
            let turn: Double = side * spread * random.range(0.7, 1.2) + random.range(-0.12, 0.12)
            let shrink: Double = random.range(0.68, 0.8)
            grow(from: end, angle: angle + turn, length: length * shrink, width: width * 0.66, depth: depth - 1, spread: spread, random: &random, twigs: &twigs, tips: &tips)
        }
        if depth <= 2 { tips.append(end) }
    }

    private static func foliage(season: Season, cherry: Bool) -> [Color] {
        switch season {
        case .winter:
            return []
        case .autumn:
            return [Color(red: 0.92, green: 0.45, blue: 0.12), Color(red: 0.8, green: 0.2, blue: 0.12), Color(red: 0.95, green: 0.7, blue: 0.2)]
        case .spring:
            if cherry {
                return [Color(red: 1, green: 0.72, blue: 0.82), Color(red: 0.98, green: 0.6, blue: 0.75), Color(red: 1, green: 0.85, blue: 0.9)]
            }
            return [Color(red: 0.48, green: 0.78, blue: 0.36), Color(red: 0.6, green: 0.85, blue: 0.4), Color(red: 0.4, green: 0.7, blue: 0.32)]
        case .summer, .none:
            if cherry {
                return [Color(red: 0.98, green: 0.7, blue: 0.8), Color(red: 0.4, green: 0.68, blue: 0.32), Color(red: 1, green: 0.82, blue: 0.88)]
            }
            return [Color(red: 0.2, green: 0.55, blue: 0.25), Color(red: 0.28, green: 0.64, blue: 0.3), Color(red: 0.16, green: 0.46, blue: 0.22)]
        }
    }

    // MARK: Pine

    private static func drawPine(in context: GraphicsContext, size: CGSize, base: CGPoint, t: Double, season: Season, random: inout GardenRandom) {
        let height: Double = Double(size.height) * (0.22 + 0.58 * t)
        let trunkWidth: Double = 3 + 7 * t
        let top = CGPoint(x: base.x, y: base.y - CGFloat(height))
        var trunk = Path()
        trunk.move(to: base)
        trunk.addLine(to: CGPoint(x: base.x, y: base.y - CGFloat(height * 0.25)))
        context.stroke(trunk, with: .color(bark), style: StrokeStyle(lineWidth: trunkWidth, lineCap: .butt))
        let tiers: Int = 2 + Int(t * 5)
        let crownHeight: Double = height * 0.85
        let widest: Double = Double(size.width) * (0.22 + 0.24 * t)
        let greens: [Color] = [Color(red: 0.1, green: 0.38, blue: 0.24), Color(red: 0.14, green: 0.46, blue: 0.28), Color(red: 0.18, green: 0.52, blue: 0.32)]
        for tier in 0..<tiers {
            let f: Double = Double(tier) / Double(max(tiers, 1))
            let bottomY: Double = Double(base.y) - height * 0.18 - crownHeight * f * 0.92
            let tierHeight: Double = crownHeight / Double(tiers) * 1.6
            let half: Double = widest * (1 - f * 0.78)
            var path = Path()
            path.move(to: CGPoint(x: Double(base.x) - half, y: bottomY))
            let teeth: Int = 4
            for tooth in 1...teeth {
                let x: Double = Double(base.x) - half + 2 * half * Double(tooth) / Double(teeth)
                path.addLine(to: CGPoint(x: x - half / Double(teeth), y: bottomY - 5))
                path.addLine(to: CGPoint(x: x, y: bottomY + random.range(-1, 3)))
            }
            path.addLine(to: CGPoint(x: Double(base.x), y: bottomY - tierHeight))
            path.closeSubpath()
            context.fill(path, with: .color(greens[tier % greens.count]))
            if season == .winter {
                var snow = Path()
                snow.move(to: CGPoint(x: Double(base.x) - half * 0.45, y: bottomY - tierHeight * 0.5))
                snow.addLine(to: CGPoint(x: Double(base.x), y: bottomY - tierHeight))
                snow.addLine(to: CGPoint(x: Double(base.x) + half * 0.45, y: bottomY - tierHeight * 0.5))
                snow.addQuadCurve(to: CGPoint(x: Double(base.x) - half * 0.45, y: bottomY - tierHeight * 0.5), control: CGPoint(x: Double(base.x), y: bottomY - tierHeight * 0.62))
                context.fill(snow, with: .color(.white.opacity(0.92)))
            }
        }
        if t > 0.65 {
            for _ in 0..<Int(2 + t * 4) {
                let x: Double = Double(base.x) + random.range(-widest * 0.5, widest * 0.5)
                let y: Double = Double(base.y) - height * random.range(0.25, 0.6)
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 5, width: 6, height: 10)), with: .color(Color(red: 0.5, green: 0.32, blue: 0.16)))
            }
        }
        _ = top
    }

    // MARK: Palm

    private static func drawPalm(in context: GraphicsContext, size: CGSize, base: CGPoint, t: Double, season: Season, random: inout GardenRandom) {
        let height: Double = Double(size.height) * (0.2 + 0.62 * t)
        let lean: Double = random.range(-0.18, 0.18) * Double(size.width)
        let top = CGPoint(x: Double(base.x) + lean, y: Double(base.y) - height)
        let control = CGPoint(x: Double(base.x) - lean * 0.6, y: Double(base.y) - height * 0.5)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: top, control: control)
        let width: Double = 4 + 8 * t
        context.stroke(trunk, with: .color(Color(red: 0.55, green: 0.42, blue: 0.27)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        // Rings on the trunk.
        let rings: Int = 4 + Int(t * 10)
        for ring in 1..<rings {
            let f: Double = Double(ring) / Double(rings)
            let x: Double = (1 - f) * (1 - f) * Double(base.x) + 2 * (1 - f) * f * Double(control.x) + f * f * Double(top.x)
            let y: Double = (1 - f) * (1 - f) * Double(base.y) + 2 * (1 - f) * f * Double(control.y) + f * f * Double(top.y)
            var mark = Path()
            mark.move(to: CGPoint(x: x - width * 0.5, y: y))
            mark.addLine(to: CGPoint(x: x + width * 0.5, y: y + 2))
            context.stroke(mark, with: .color(Color(red: 0.38, green: 0.27, blue: 0.16).opacity(0.7)), lineWidth: 1.2)
        }
        let fronds: Int = 5 + Int(t * 4)
        let reach: Double = Double(size.width) * (0.16 + 0.3 * t)
        let leaf: Color = season == .autumn ? Color(red: 0.55, green: 0.62, blue: 0.22) : Color(red: 0.2, green: 0.58, blue: 0.28)
        for frond in 0..<fronds {
            let a: Double = -Double.pi + Double.pi * (Double(frond) + 0.5) / Double(fronds)
            let end = CGPoint(x: Double(top.x) + Math.cosine(a) * reach, y: Double(top.y) + Math.sine(a) * reach * 0.35 + reach * 0.45)
            let bendPoint = CGPoint(x: Double(top.x) + Math.cosine(a) * reach * 0.6, y: Double(top.y) - reach * 0.25)
            var stem = Path()
            stem.move(to: top)
            stem.addQuadCurve(to: end, control: bendPoint)
            context.stroke(stem, with: .color(leaf), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            for step in 1..<9 {
                let f: Double = Double(step) / 9
                let x: Double = (1 - f) * (1 - f) * Double(top.x) + 2 * (1 - f) * f * Double(bendPoint.x) + f * f * Double(end.x)
                let y: Double = (1 - f) * (1 - f) * Double(top.y) + 2 * (1 - f) * f * Double(bendPoint.y) + f * f * Double(end.y)
                let leafLength: Double = 9 * (1 - f * 0.6) * (0.6 + t)
                var blade = Path()
                blade.move(to: CGPoint(x: x, y: y))
                blade.addLine(to: CGPoint(x: x + Math.cosine(a + 1.2) * leafLength, y: y + leafLength))
                blade.move(to: CGPoint(x: x, y: y))
                blade.addLine(to: CGPoint(x: x + Math.cosine(a - 1.2) * leafLength, y: y + leafLength))
                context.stroke(blade, with: .color(leaf.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        if t > 0.6 {
            for index in 0..<3 {
                let x: Double = Double(top.x) + Double(index - 1) * 6
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: Double(top.y) + 2, width: 8, height: 8)), with: .color(Color(red: 0.42, green: 0.3, blue: 0.15)))
            }
        }
    }

    // MARK: Cactus

    private static func drawCactus(in context: GraphicsContext, size: CGSize, base: CGPoint, t: Double, season: Season) {
        let height: Double = Double(size.height) * (0.18 + 0.6 * t)
        let width: Double = Double(size.width) * (0.1 + 0.08 * t)
        let green = Color(red: 0.3, green: 0.58, blue: 0.36)
        let dark = Color(red: 0.2, green: 0.45, blue: 0.28)
        let body = Path(roundedRect: CGRect(x: Double(base.x) - width / 2, y: Double(base.y) - height, width: width, height: height), cornerRadius: width / 2)
        context.fill(body, with: .color(green))
        func arm(_ side: Double, at f: Double, rise: Double) {
            let y: Double = Double(base.y) - height * f
            let out: Double = width * 1.1
            var path = Path()
            path.move(to: CGPoint(x: Double(base.x) + side * width * 0.3, y: y))
            path.addLine(to: CGPoint(x: Double(base.x) + side * out, y: y))
            path.addLine(to: CGPoint(x: Double(base.x) + side * out, y: y - rise))
            context.stroke(path, with: .color(green), style: StrokeStyle(lineWidth: width * 0.62, lineCap: .round, lineJoin: .round))
        }
        if t > 0.35 { arm(-1, at: 0.45, rise: height * 0.32 * min((t - 0.35) * 3, 1)) }
        if t > 0.6 { arm(1, at: 0.6, rise: height * 0.26 * min((t - 0.6) * 3, 1)) }
        // Ribs and spines.
        for rib in [-0.22, 0.0, 0.22] {
            var line = Path()
            line.move(to: CGPoint(x: Double(base.x) + rib * width, y: Double(base.y) - height + width * 0.4))
            line.addLine(to: CGPoint(x: Double(base.x) + rib * width, y: Double(base.y) - 2))
            context.stroke(line, with: .color(dark.opacity(0.7)), lineWidth: 1)
        }
        var y: Double = Double(base.y) - 8
        while y > Double(base.y) - height + 6 {
            for side in [-0.5, 0.5] {
                context.fill(Path(ellipseIn: CGRect(x: Double(base.x) + side * width - 1, y: y, width: 2, height: 2)), with: .color(.white.opacity(0.8)))
            }
            y -= 9
        }
        if season == .winter {
            let cap = Path(ellipseIn: CGRect(x: Double(base.x) - width / 2, y: Double(base.y) - height - 2, width: width, height: width * 0.45))
            context.fill(cap, with: .color(.white))
        } else if t > 0.75 && (season == .spring || season == .summer || season == .none) {
            let center = CGPoint(x: Double(base.x), y: Double(base.y) - height - 3)
            for petal in 0..<6 {
                var c = context
                c.translateBy(x: center.x, y: center.y)
                c.rotate(by: .radians(Double(petal) * Double.pi / 3))
                c.fill(Path(ellipseIn: CGRect(x: 0, y: -2.5, width: 9, height: 5)), with: .color(Color(red: 1, green: 0.45, blue: 0.62)))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(.yellow))
        }
    }

    // MARK: Sunflower

    private static func drawSunflower(in context: GraphicsContext, size: CGSize, base: CGPoint, t: Double, season: Season) {
        let height: Double = Double(size.height) * (0.2 + 0.52 * t)
        let droop: Double = season == .autumn || season == .winter ? 0.35 : 0
        let top = CGPoint(x: Double(base.x) + droop * 20, y: Double(base.y) - height + droop * 10)
        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: top, control: CGPoint(x: Double(base.x) - 8, y: Double(base.y) - height * 0.5))
        let green: Color = season == .winter ? Color(red: 0.5, green: 0.45, blue: 0.3) : Color(red: 0.32, green: 0.6, blue: 0.26)
        context.stroke(stem, with: .color(green), style: StrokeStyle(lineWidth: 3 + 3 * t, lineCap: .round))
        let leaves: Int = 2 + Int(t * 5)
        for index in 0..<leaves {
            let f: Double = 0.18 + 0.7 * Double(index) / Double(max(leaves, 1))
            let y: Double = Double(base.y) - height * f
            let side: Double = index % 2 == 0 ? -1 : 1
            var leaf = context
            leaf.translateBy(x: base.x - 4 * CGFloat(f), y: CGFloat(y))
            leaf.rotate(by: .radians(side * 0.5 + (side < 0 ? Double.pi : 0)))
            let length: Double = 12 + 16 * t * (1 - f * 0.5)
            leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -length * 0.3, width: length, height: length * 0.6)), with: .color(green))
        }
        guard t > 0.4 else {
            context.fill(Path(ellipseIn: CGRect(x: top.x - 5, y: top.y - 5, width: 10, height: 10)), with: .color(green))
            return
        }
        let bloom: Double = min((t - 0.4) / 0.4, 1)
        let disk: Double = 7 + 13 * bloom
        let petalLength: Double = disk * 0.9
        let petal: Color = season == .winter ? Color(red: 0.55, green: 0.4, blue: 0.2) : Color(red: 1, green: 0.8, blue: 0.1)
        let petals: Int = 18
        for index in 0..<petals {
            var c = context
            c.translateBy(x: top.x, y: top.y)
            c.rotate(by: .radians(Double(index) * 2 * Double.pi / Double(petals)))
            c.fill(Path(ellipseIn: CGRect(x: disk * 0.7, y: -petalLength * 0.18, width: petalLength, height: petalLength * 0.36)), with: .color(petal))
        }
        context.fill(Path(ellipseIn: CGRect(x: Double(top.x) - disk, y: Double(top.y) - disk, width: disk * 2, height: disk * 2)), with: .color(Color(red: 0.36, green: 0.22, blue: 0.1)))
        // Seeds in the golden-angle spiral.
        let seeds: Int = Int(20 + 50 * bloom)
        for index in 0..<seeds {
            let a: Double = Double(index) * 2.39996
            let r: Double = disk * 0.9 * Math.root(Double(index) / Double(seeds))
            let x: Double = Double(top.x) + Math.cosine(a) * r
            let y: Double = Double(top.y) + Math.sine(a) * r
            context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color(red: 0.6, green: 0.42, blue: 0.15)))
        }
    }

    // MARK: Bonsai

    private static func drawBonsai(in context: GraphicsContext, size: CGSize, base: CGPoint, t: Double, season: Season, random: inout GardenRandom) {
        let potWidth: Double = Double(size.width) * 0.5
        let potHeight: Double = 16
        var pot = Path()
        pot.move(to: CGPoint(x: Double(base.x) - potWidth / 2, y: Double(base.y) - potHeight))
        pot.addLine(to: CGPoint(x: Double(base.x) + potWidth / 2, y: Double(base.y) - potHeight))
        pot.addLine(to: CGPoint(x: Double(base.x) + potWidth / 2 - 8, y: Double(base.y)))
        pot.addLine(to: CGPoint(x: Double(base.x) - potWidth / 2 + 8, y: Double(base.y)))
        pot.closeSubpath()
        context.fill(pot, with: .color(Color(red: 0.25, green: 0.38, blue: 0.55)))
        let rim = Path(roundedRect: CGRect(x: Double(base.x) - potWidth / 2 - 3, y: Double(base.y) - potHeight - 4, width: potWidth + 6, height: 5), cornerRadius: 2)
        context.fill(rim, with: .color(Color(red: 0.2, green: 0.3, blue: 0.45)))
        let soilTop = CGPoint(x: base.x, y: base.y - CGFloat(potHeight) - 3)
        if t < 0.1 {
            drawSprout(in: context, at: soilTop, growth: 0.08 + t, season: season)
            return
        }
        let g: Double = (t - 0.1) / 0.9
        let height: Double = Double(size.height) * (0.15 + 0.4 * g)
        // A twisted trunk.
        let mid = CGPoint(x: Double(soilTop.x) - height * 0.35, y: Double(soilTop.y) - height * 0.45)
        let top = CGPoint(x: Double(soilTop.x) + height * 0.15, y: Double(soilTop.y) - height)
        var trunk = Path()
        trunk.move(to: soilTop)
        trunk.addCurve(to: top, control1: CGPoint(x: Double(soilTop.x) + height * 0.3, y: Double(soilTop.y) - height * 0.2), control2: mid)
        context.stroke(trunk, with: .color(bark), style: StrokeStyle(lineWidth: 4 + 7 * g, lineCap: .round))
        // Flat pads of foliage.
        let pads: Int = 1 + Int(g * 4)
        let foliage: [Color] = season == .autumn
            ? [Color(red: 0.85, green: 0.38, blue: 0.15), Color(red: 0.75, green: 0.25, blue: 0.15)]
            : [Color(red: 0.2, green: 0.5, blue: 0.26), Color(red: 0.28, green: 0.6, blue: 0.3)]
        for pad in 0..<pads {
            let f: Double = pad == 0 ? 1 : random.range(0.45, 0.85)
            let side: Double = pad == 0 ? 0 : (pad % 2 == 0 ? 1 : -1)
            let center = CGPoint(x: Double(top.x) + side * height * random.range(0.22, 0.36), y: Double(soilTop.y) - height * f)
            if pad > 0 {
                var limb = Path()
                limb.move(to: CGPoint(x: Double(top.x) - side * 4, y: Double(soilTop.y) - height * f + 6))
                limb.addLine(to: center)
                context.stroke(limb, with: .color(bark), style: StrokeStyle(lineWidth: 2 + 2 * g, lineCap: .round))
            }
            let padWidth: Double = 24 + 22 * g
            for blob in 0..<4 {
                let x: Double = Double(center.x) + (Double(blob) - 1.5) * padWidth * 0.22
                let rect = CGRect(x: x - padWidth * 0.25, y: Double(center.y) - 9 - Double(blob % 2) * 3, width: padWidth * 0.5, height: 16)
                let color: Color = season == .winter ? .white : foliage[blob % foliage.count]
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.92)))
            }
        }
    }
}

// MARK: A living plant

/// A plant that sways in the wind and can be watched growing: its growth
/// animates when it changes.
struct LivingPlant: View, Animatable {
    var growth: Double
    let species: PlantSpecies
    let season: Season
    let seed: UInt64
    var sways = true
    var ground = true
    @State private var phase = false

    var animatableData: Double {
        get { growth }
        set { growth = newValue }
    }

    var body: some View {
        let drawn: Double = growth
        let kind: PlantSpecies = species
        let time: Season = season
        let number: UInt64 = seed
        let hasGround: Bool = ground
        Canvas { context, size in
            TreePainter.draw(kind, in: context, size: size, growth: drawn, season: time, seed: number, ground: hasGround)
        }
        .rotationEffect(.degrees(sways ? (phase ? 1.4 : -1.4) : 0), anchor: .bottom)
        .onAppear { startSwaying() }
        .onChange(of: sways) { startSwaying() }
        .accessibilityHidden(true)
    }

    private func startSwaying() {
        guard sways else {
            phase = false
            return
        }
        let pace: Double = 2.6 + Double(seed % 7) * 0.25
        withAnimation(.easeInOut(duration: pace).repeatForever(autoreverses: true)) { phase = true }
    }
}
