import SwiftUI

/// How a mind map looks: its layout, branches, idea shapes, colors, font
/// and background. Each map has its own; every part can be mixed freely.
struct MindMapStyle: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case free, right, balanced, radial, tree, orgChart
        var id: Self { self }

        var title: String {
            switch self {
            case .free: "Free (as Placed)"
            case .right: "Growing Right"
            case .balanced: "Both Sides"
            case .radial: "Radial"
            case .tree: "Real Tree"
            case .orgChart: "Org Chart"
            }
        }

        var systemImage: String {
            switch self {
            case .free: "hand.draw"
            case .right: "arrow.right.circle"
            case .balanced: "arrow.left.and.right.circle"
            case .radial: "sun.max"
            case .tree: "tree"
            case .orgChart: "rectangle.3.group"
            }
        }
    }

    enum Branch: String, Codable, CaseIterable, Identifiable {
        case curved, organic, straight, elbow, wood
        var id: Self { self }

        var title: String {
            switch self {
            case .curved: "Curved"
            case .organic: "Organic (Tapered)"
            case .straight: "Straight"
            case .elbow: "Elbow"
            case .wood: "Wooden Branches"
            }
        }
    }

    enum NodeShape: String, Codable, CaseIterable, Identifiable {
        case capsule, rounded, box, circle, cloud, leaf, underline, plain
        var id: Self { self }

        var title: String {
            switch self {
            case .capsule: "Capsule"
            case .rounded: "Rounded"
            case .box: "Box"
            case .circle: "Circle"
            case .cloud: "Cloud"
            case .leaf: "Leaf"
            case .underline: "Underline"
            case .plain: "Text Only"
            }
        }

        var systemImage: String {
            switch self {
            case .capsule: "capsule"
            case .rounded: "app"
            case .box: "rectangle"
            case .circle: "circle"
            case .cloud: "cloud"
            case .leaf: "leaf"
            case .underline: "underline"
            case .plain: "textformat"
            }
        }
    }

    enum Palette: String, Codable, CaseIterable, Identifiable {
        case rainbow, ocean, forest, autumn, sunset, pastel, mono
        var id: Self { self }
        var title: String { rawValue.capitalized }

        var colors: [Color] {
            switch self {
            case .rainbow: [.blue, .orange, .green, .pink, .teal, .red, .indigo, .yellow]
            case .ocean: [Color(red: 0.1, green: 0.45, blue: 0.8), .teal, .cyan, Color(red: 0.2, green: 0.3, blue: 0.7), .mint, .blue]
            case .forest: [Color(red: 0.2, green: 0.55, blue: 0.25), Color(red: 0.45, green: 0.65, blue: 0.2), .mint, Color(red: 0.3, green: 0.45, blue: 0.2), .teal, Color(red: 0.55, green: 0.7, blue: 0.3)]
            case .autumn: [Color(red: 0.85, green: 0.45, blue: 0.1), Color(red: 0.8, green: 0.25, blue: 0.15), Color(red: 0.9, green: 0.7, blue: 0.15), Color(red: 0.6, green: 0.35, blue: 0.15), .orange, .brown]
            case .sunset: [.orange, .pink, .purple, Color(red: 1, green: 0.4, blue: 0.4), .yellow, .indigo]
            case .pastel: [Color(red: 0.6, green: 0.75, blue: 1), Color(red: 1, green: 0.7, blue: 0.75), Color(red: 0.65, green: 0.9, blue: 0.7), Color(red: 1, green: 0.85, blue: 0.55), Color(red: 0.8, green: 0.7, blue: 1), Color(red: 0.6, green: 0.9, blue: 0.9)]
            case .mono: [Color.inkAccent]
            }
        }
    }

    var layout = Layout.right
    var branch = Branch.curved
    var shape = NodeShape.capsule
    /// The central idea's shape.
    var rootShape = NodeShape.capsule
    var palette = Palette.rainbow
    var font = ThemeRecipe.FontStyle.standard
    var glow = true
    var backdrop = ScreenBackdrop.plain
    /// How far apart ideas sit (1 is normal).
    var spacing = 1.0

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = container.value(.layout, or: layout)
        branch = container.value(.branch, or: branch)
        shape = container.value(.shape, or: shape)
        rootShape = container.value(.rootShape, or: rootShape)
        palette = container.value(.palette, or: palette)
        font = container.value(.font, or: font)
        glow = container.value(.glow, or: glow)
        backdrop = container.value(.backdrop, or: backdrop)
        spacing = container.value(.spacing, or: spacing)
    }

    /// Ready-made combinations.
    static let presets: [(name: String, systemImage: String, style: MindMapStyle)] = {
        var classic = MindMapStyle()
        classic.glow = true

        var tree = MindMapStyle()
        tree.layout = .tree
        tree.branch = .wood
        tree.shape = .leaf
        tree.rootShape = .circle
        tree.palette = .forest
        tree.backdrop = .spring
        tree.font = .rounded

        var autumnTree = tree
        autumnTree.palette = .autumn
        autumnTree.backdrop = .autumn

        var buzan = MindMapStyle()
        buzan.layout = .radial
        buzan.branch = .organic
        buzan.shape = .underline
        buzan.rootShape = .cloud
        buzan.palette = .rainbow
        buzan.font = .rounded

        var org = MindMapStyle()
        org.layout = .orgChart
        org.branch = .elbow
        org.shape = .box
        org.rootShape = .box
        org.palette = .ocean
        org.glow = false

        var notebook = MindMapStyle()
        notebook.layout = .balanced
        notebook.branch = .straight
        notebook.shape = .plain
        notebook.rootShape = .rounded
        notebook.palette = .mono
        notebook.font = .serif
        notebook.backdrop = .oldPaper
        notebook.glow = false

        var dream = MindMapStyle()
        dream.layout = .radial
        dream.branch = .curved
        dream.shape = .cloud
        dream.rootShape = .cloud
        dream.palette = .pastel
        dream.backdrop = .glass
        dream.font = .rounded

        return [
            ("Classic", "point.3.connected.trianglepath.dotted", classic),
            ("Spring Tree", "tree", tree),
            ("Autumn Tree", "leaf", autumnTree),
            ("Organic", "scribble.variable", buzan),
            ("Org Chart", "rectangle.3.group", org),
            ("Notebook", "book", notebook),
            ("Dreamy", "cloud", dream),
        ]
    }()
}

extension MindMap {
    var appliedStyle: MindMapStyle { style ?? MindMapStyle() }

    /// Places every idea for a layout. `free` leaves them where they are.
    mutating func arrange(_ layout: MindMapStyle.Layout, spacing: Double = 1) {
        switch layout {
        case .free: break
        case .right: autoLayout(horizontalSpacing: 230 * spacing, verticalSpacing: 64 * spacing)
        case .balanced: arrangeBalanced(spacing)
        case .radial: arrangeRadial(spacing, from: -.pi, to: .pi, step: 210)
        case .tree: arrangeRadial(spacing, from: -.pi * 0.95, to: -.pi * 0.05, step: 215)
        case .orgChart: arrangeTopDown(spacing)
        }
    }

    /// Leaves under each idea, so branches get room in proportion.
    private func leafCounts() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        func count(_ id: UUID, visited: inout Set<UUID>) -> Int {
            guard visited.insert(id).inserted else { return 0 }
            let kids = children(of: id)
            let total = kids.isEmpty ? 1 : kids.reduce(0) { $0 + count($1.id, visited: &visited) }
            counts[id] = total
            return total
        }
        var visited: Set<UUID> = []
        if let root { _ = count(root.id, visited: &visited) }
        return counts
    }

    private mutating func set(_ positions: [UUID: CGPoint]) {
        for index in nodes.indices {
            if let point = positions[nodes[index].id] {
                nodes[index].x = Double(point.x)
                nodes[index].y = Double(point.y)
            }
        }
    }

    /// Main branches alternate left and right of the central idea.
    private mutating func arrangeBalanced(_ spacing: Double) {
        guard let root else { return }
        let counts = leafCounts()
        let gapX = 230 * spacing
        let gapY = 64 * spacing
        var positions: [UUID: CGPoint] = [root.id: .zero]
        let mains = children(of: root.id)
        let sides = [mains.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element),
                     mains.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)]
        for (side, branches) in sides.enumerated() {
            let direction: Double = side == 0 ? 1 : -1
            let total = Double(branches.reduce(0) { $0 + (counts[$1.id] ?? 1) }) * gapY
            var top = -total / 2
            func place(_ id: UUID, depth: Int, top: Double) {
                let span = Double(counts[id] ?? 1) * gapY
                positions[id] = CGPoint(x: Double(depth) * gapX * direction, y: top + span / 2)
                var childTop = top
                for child in children(of: id) where positions[child.id] == nil {
                    place(child.id, depth: depth + 1, top: childTop)
                    childTop += Double(counts[child.id] ?? 1) * gapY
                }
            }
            for branch in branches {
                place(branch.id, depth: 1, top: top)
                top += Double(counts[branch.id] ?? 1) * gapY
            }
        }
        set(positions)
    }

    /// Ideas in rings around the central one, each branch in its own slice.
    /// With an upward slice it grows like a tree from its trunk.
    private mutating func arrangeRadial(_ spacing: Double, from start: Double, to end: Double, step: Double) {
        guard let root else { return }
        let counts = leafCounts()
        var positions: [UUID: CGPoint] = [root.id: .zero]
        func place(_ id: UUID, depth: Int, from a: Double, to b: Double) {
            let kids = children(of: id).filter { positions[$0.id] == nil }
            let total = Double(kids.reduce(0) { $0 + (counts[$1.id] ?? 1) })
            var angle = a
            for (order, kid) in kids.enumerated() {
                let share = (b - a) * Double(counts[kid.id] ?? 1) / max(total, 1)
                let middle = angle + share / 2
                // Rings get a little tighter further out; crowded ideas
                // step in and out so their labels don't overlap.
                let crowded = depth > 0 && kids.count > 2 && !order.isMultiple(of: 2)
                let ring: Double = step * spacing * (Double(depth) + 1)
                let tighten: Double = depth == 0 ? 1.1 : 0.95
                let stagger: Double = crowded ? 70 * spacing : 0
                let radius: Double = ring * tighten + stagger
                let x: Double = Math.cosine(middle) * radius
                let y: Double = Math.sine(middle) * radius
                positions[kid.id] = CGPoint(x: x, y: y)
                place(kid.id, depth: depth + 1, from: angle, to: angle + share)
                angle += share
            }
        }
        place(root.id, depth: 0, from: start, to: end)
        set(positions)
    }

    /// The central idea on top, branches below, like an org chart.
    private mutating func arrangeTopDown(_ spacing: Double) {
        guard let root else { return }
        let counts = leafCounts()
        let gapX = 190 * spacing
        let gapY = 130 * spacing
        var positions: [UUID: CGPoint] = [:]
        func place(_ id: UUID, depth: Int, left: Double) {
            let span = Double(counts[id] ?? 1) * gapX
            positions[id] = CGPoint(x: left + span / 2, y: Double(depth) * gapY)
            var childLeft = left
            for child in children(of: id) where positions[child.id] == nil {
                place(child.id, depth: depth + 1, left: childLeft)
                childLeft += Double(counts[child.id] ?? 1) * gapX
            }
        }
        let total = Double(counts[root.id] ?? 1) * gapX
        place(root.id, depth: 0, left: -total / 2)
        set(positions)
    }
}
