import SwiftUI

/// How the graph looks and how its notes are arranged (Customize, and the
/// Arrange menu).
struct GraphLook: StoredLook {
    static let storageKey = "graphLook"

    enum Arrangement: String, Codable, CaseIterable, Identifiable {
        case web, folders, timeline, radial, tree, grid, manual
        var id: Self { self }

        var title: String {
            switch self {
            case .web: "Web"
            case .folders: "Folder Islands"
            case .timeline: "Timeline"
            case .radial: "Around a Note"
            case .tree: "Tree"
            case .grid: "Grid"
            case .manual: "By Hand"
            }
        }

        var systemImage: String {
            switch self {
            case .web: "circle.hexagongrid"
            case .folders: "circle.grid.2x2"
            case .timeline: "calendar.day.timeline.left"
            case .radial: "smallcircle.filled.circle"
            case .tree: "point.3.connected.trianglepath.dotted"
            case .grid: "square.grid.3x3"
            case .manual: "hand.draw"
            }
        }

        var detail: String {
            switch self {
            case .web: "Linked notes pull together, others drift apart."
            case .folders: "Each folder is an island with its notes around it."
            case .timeline: "Oldest to newest, left to right; links arc above."
            case .radial: "The chosen note in the middle, its links in rings around it."
            case .tree: "The chosen note on top, links branching down."
            case .grid: "Neat rows, A to Z."
            case .manual: "Drag notes anywhere; the places are kept."
            }
        }
    }

    enum NodeStyle: String, Codable, CaseIterable, Identifiable {
        case glow, bubble, card, dot
        var id: Self { self }
        var title: String {
            switch self {
            case .glow: "Glowing Dots"
            case .bubble: "Bubbles"
            case .card: "Cards"
            case .dot: "Small Dots"
            }
        }
    }

    enum EdgeStyle: String, Codable, CaseIterable, Identifiable {
        case straight, curved, dashed
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    enum ColorBy: String, Codable, CaseIterable, Identifiable {
        case kind, folder, age
        var id: Self { self }
        var title: String {
            switch self {
            case .kind: "Note Kind"
            case .folder: "Folder"
            case .age: "Age"
            }
        }
    }

    var arrangement = Arrangement.web
    var nodeStyle = NodeStyle.glow
    var edgeStyle = EdgeStyle.straight
    var colorBy = ColorBy.kind
    var sizeByLinks = true
    var showsLabels = true
    var backdrop = ScreenBackdrop.plain
    /// Where notes were dragged in By Hand.
    var manual: [String: CGPoint] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrangement = container.value(.arrangement, or: arrangement)
        nodeStyle = container.value(.nodeStyle, or: nodeStyle)
        edgeStyle = container.value(.edgeStyle, or: edgeStyle)
        colorBy = container.value(.colorBy, or: colorBy)
        sizeByLinks = container.value(.sizeByLinks, or: sizeByLinks)
        showsLabels = container.value(.showsLabels, or: showsLabels)
        backdrop = container.value(.backdrop, or: backdrop)
        manual = container.value(.manual, or: manual)
    }
}

/// A labelled area drawn behind an arrangement (folder islands, timeline
/// months, rings).
struct GraphGuide: Equatable {
    enum Kind: Equatable {
        case island(radius: CGFloat)
        case ring(radius: CGFloat)
        case axis(from: CGFloat, to: CGFloat)
        case tick
    }

    let kind: Kind
    let center: CGPoint
    let title: String
    let colorIndex: Int
}

struct GraphArrangement {
    var positions: [String: CGPoint] = [:]
    var guides: [GraphGuide] = []
}

extension NoteGraph {
    /// Places the nodes for an arrangement that isn't the force web.
    func arrange(_ arrangement: GraphLook.Arrangement, focus: String?, folderNames: [UUID: String], manual: [String: CGPoint], current: [String: CGPoint]) -> GraphArrangement {
        switch arrangement {
        case .web: return GraphArrangement(positions: current)
        case .folders: return folderIslands(folderNames: folderNames)
        case .timeline: return timeline()
        case .radial: return radial(focus: focus)
        case .tree: return tree(focus: focus)
        case .grid: return grid()
        case .manual:
            var positions = current
            for (id, point) in manual where positions[id] != nil || nodes.contains(where: { $0.id == id }) {
                positions[id] = point
            }
            return GraphArrangement(positions: positions)
        }
    }

    /// The most connected note, used when none is chosen.
    var hub: String? {
        nodes.filter { !$0.isTag }.max { degree(of: $0.id) < degree(of: $1.id) }?.id ?? nodes.first?.id
    }

    private func spiral(_ count: Int, around center: CGPoint, spacing: CGFloat = 34) -> [CGPoint] {
        (0..<count).map { index in
            let angle: Double = Double(index) * 2.399963
            let away: CGFloat = spacing * CGFloat(Math.root(Double(index))) + 18
            let radius: CGFloat = index == 0 ? 0 : away
            let x: CGFloat = center.x + radius * CGFloat(Math.cosine(angle))
            let y: CGFloat = center.y + radius * CGFloat(Math.sine(angle))
            return CGPoint(x: x, y: y)
        }
    }

    private func folderIslands(folderNames: [UUID: String]) -> GraphArrangement {
        // Group notes by folder; tags make their own island.
        var groups: [(key: String, title: String, ids: [String])] = []
        var index: [String: Int] = [:]
        for node in nodes {
            let key = node.isTag ? "#tags" : node.folderID?.uuidString ?? "unfiled"
            let title = node.isTag ? "Tags" : node.folderID.flatMap { folderNames[$0] } ?? "Unfiled"
            if let at = index[key] {
                groups[at].ids.append(node.id)
            } else {
                index[key] = groups.count
                groups.append((key, title, [node.id]))
            }
        }
        var result = GraphArrangement()
        let ringRadius: CGFloat = groups.count <= 1 ? 0 : CGFloat(160 + groups.count * 40)
        for (offset, group) in groups.enumerated() {
            let turn: Double = Double(offset) / Double(max(groups.count, 1))
            let angle: Double = turn * 2 * Double.pi - Double.pi / 2
            let center = CGPoint(x: ringRadius * CGFloat(Math.cosine(angle)), y: ringRadius * CGFloat(Math.sine(angle)))
            let points = spiral(group.ids.count, around: center)
            for (id, point) in zip(group.ids, points) { result.positions[id] = point }
            let radius: CGFloat = 34 * CGFloat(Math.root(Double(max(group.ids.count - 1, 0)))) + 60
            result.guides.append(GraphGuide(kind: .island(radius: radius), center: center, title: group.title, colorIndex: offset))
        }
        return result
    }

    private func timeline() -> GraphArrangement {
        var result = GraphArrangement()
        let notes = nodes.filter { !$0.isTag }.sorted { $0.date < $1.date }
        let spacing: CGFloat = 96
        let width = CGFloat(max(notes.count - 1, 0)) * spacing
        var lastMonth = ""
        for (offset, node) in notes.enumerated() {
            let x = CGFloat(offset) * spacing - width / 2
            // Alternate above and below the axis so titles don't overlap.
            let y: CGFloat = offset.isMultiple(of: 2) ? -40 : 40
            result.positions[node.id] = CGPoint(x: x, y: y)
            let month = node.date.formatted(.dateTime.month(.abbreviated).year())
            if month != lastMonth {
                result.guides.append(GraphGuide(kind: .tick, center: CGPoint(x: x, y: 0), title: month, colorIndex: 0))
                lastMonth = month
            }
        }
        result.guides.append(GraphGuide(kind: .axis(from: -width / 2 - 60, to: width / 2 + 60), center: .zero, title: "", colorIndex: 0))
        // Tags sit under the notes that use them.
        for tag in nodes where tag.isTag {
            let xs = neighbors(of: tag.id).compactMap { result.positions[$0]?.x }
            let x = xs.isEmpty ? 0 : xs.reduce(0, +) / CGFloat(xs.count)
            result.positions[tag.id] = CGPoint(x: x, y: 170)
        }
        return result
    }

    /// Breadth-first steps from `root` through links.
    private func levels(from root: String) -> [String: Int] {
        var distance = [root: 0]
        var queue = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for next in neighbors(of: current).sorted() where distance[next] == nil {
                distance[next] = distance[current]! + 1
                queue.append(next)
            }
        }
        return distance
    }

    private func radial(focus: String?) -> GraphArrangement {
        var result = GraphArrangement()
        guard let root = focus ?? hub else { return result }
        let distance = levels(from: root)
        let maxLevel = distance.values.max() ?? 0
        var rings: [Int: [String]] = [:]
        for node in nodes {
            rings[distance[node.id] ?? maxLevel + 1, default: []].append(node.id)
        }
        let step: CGFloat = 150
        for (level, ids) in rings {
            guard level > 0 else {
                result.positions[root] = .zero
                continue
            }
            let radius = CGFloat(level) * step
            for (offset, id) in ids.sorted().enumerated() {
                let turn: Double = Double(offset) / Double(ids.count)
                let angle: Double = turn * 2 * Double.pi - Double.pi / 2 + Double(level) * 0.4
                result.positions[id] = CGPoint(x: radius * CGFloat(Math.cosine(angle)), y: radius * CGFloat(Math.sine(angle)))
            }
            let title = level > maxLevel ? "Not linked" : level == 1 ? "1 link away" : "\(level) links away"
            result.guides.append(GraphGuide(kind: .ring(radius: radius), center: .zero, title: title, colorIndex: level))
        }
        return result
    }

    private func tree(focus: String?) -> GraphArrangement {
        var result = GraphArrangement()
        guard let root = focus ?? hub else { return result }
        let distance = levels(from: root)
        let maxLevel = distance.values.max() ?? 0
        var rows: [Int: [String]] = [:]
        for node in nodes {
            rows[distance[node.id] ?? maxLevel + 1, default: []].append(node.id)
        }
        let rowHeight: CGFloat = 130
        let spacing: CGFloat = 120
        var placedX: [String: CGFloat] = [:]
        for level in rows.keys.sorted() {
            // Children follow their parent's order, so branches don't cross much.
            let ids = rows[level]!.sorted { a, b in
                parentX(of: a, placed: placedX) < parentX(of: b, placed: placedX)
            }
            let width = CGFloat(ids.count - 1) * spacing
            for (offset, id) in ids.enumerated() {
                let x = CGFloat(offset) * spacing - width / 2
                let y = CGFloat(level) * rowHeight - CGFloat(maxLevel) * rowHeight / 2
                result.positions[id] = CGPoint(x: x, y: y)
                placedX[id] = x
            }
        }
        return result
    }

    private func parentX(of id: String, placed: [String: CGFloat]) -> CGFloat {
        let xs = neighbors(of: id).compactMap { placed[$0] }
        return xs.isEmpty ? .infinity : xs.reduce(0, +) / CGFloat(xs.count)
    }

    private func grid() -> GraphArrangement {
        var result = GraphArrangement()
        let sorted = nodes.sorted { ($0.isTag ? 1 : 0, $0.title.lowercased()) < ($1.isTag ? 1 : 0, $1.title.lowercased()) }
        let wide: Double = Math.root(Double(sorted.count)) * 1.4
        let columns: Int = max(Int(Math.roundUp(wide)), 1)
        let rows: Int = Int(Math.roundUp(Double(sorted.count) / Double(columns)))
        let spacingX: CGFloat = 150
        let spacingY: CGFloat = 110
        for (offset, node) in sorted.enumerated() {
            let column = offset % columns
            let row = offset / columns
            result.positions[node.id] = CGPoint(
                x: CGFloat(column) * spacingX - CGFloat(columns - 1) * spacingX / 2,
                y: CGFloat(row) * spacingY - CGFloat(rows - 1) * spacingY / 2
            )
        }
        return result
    }
}

/// Customize the graph.
struct GraphStyleView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var look: GraphLook

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $look.arrangement) {
                        ForEach(GraphLook.Arrangement.allCases) { arrangement in
                            Label(tr(arrangement.title), systemImage: arrangement.systemImage).tag(arrangement)
                        }
                    } label: {
                        Label("Arrange", systemImage: "circle.grid.cross")
                    }
                } header: {
                    Text("Arrangement")
                } footer: {
                    Text(look.arrangement.detail + (look.arrangement == .manual ? "" : " Dragging a note switches to By Hand."))
                }

                Section("Notes") {
                    Picker(selection: $look.nodeStyle) {
                        ForEach(GraphLook.NodeStyle.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Shape", systemImage: "circle.circle")
                    }
                    Picker(selection: $look.colorBy) {
                        ForEach(GraphLook.ColorBy.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Color By", systemImage: "paintpalette")
                    }
                    Toggle(isOn: $look.sizeByLinks) {
                        Label("Bigger When More Linked", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Toggle(isOn: $look.showsLabels) {
                        Label("Titles", systemImage: "textformat")
                    }
                }

                Section("Links") {
                    Picker(selection: $look.edgeStyle) {
                        ForEach(GraphLook.EdgeStyle.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Lines", systemImage: "line.diagonal")
                    }
                }

                Section("Background") {
                    BackdropPicker(backdrop: $look.backdrop)
                }

                Section {
                    if !look.manual.isEmpty {
                        Button("Forget Hand-Placed Positions", role: .destructive) {
                            look.manual = [:]
                        }
                    }
                    Button("Reset to Default", role: .destructive) {
                        let manual = look.manual
                        look = GraphLook()
                        look.manual = manual
                    }
                }
            }
            .navigationTitle("Customize Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
