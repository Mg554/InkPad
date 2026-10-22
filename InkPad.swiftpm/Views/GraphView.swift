import SwiftUI

/// Obsidian-style graph: every note as a glowing dot, [[links]] as lines,
/// and optionally #tags as their own dots. Pan, pinch, tap a note to see its
/// connections, then open it.
struct GraphView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.noteNavigation) private var navigation

    @AppStorage("graphShowsTags") private var showsTags = true
    @AppStorage("graphShowsOrphans") private var showsOrphans = true
    @State private var layout: [String: CGPoint] = [:]
    @State private var layoutKey = ""
    @State private var selected: String?
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat?

    private var currentGraph: NoteGraph {
        NoteGraph(store: store, showsTags: showsTags, showsOrphans: showsOrphans)
    }

    var body: some View {
        let graph = currentGraph
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture { withAnimation(.snappy) { selected = nil } }

                Canvas { context, size in
                    for edge in graph.edges {
                        guard let a = layout[edge.from], let b = layout[edge.to] else { continue }
                        let highlighted = selected != nil && (edge.from == selected || edge.to == selected)
                        var path = Path()
                        path.move(to: screen(a, in: size))
                        path.addLine(to: screen(b, in: size))
                        let color: Color = edge.isTag ? .teal : .purple
                        if highlighted {
                            context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 7)
                        }
                        context.stroke(path, with: .color(color.opacity(highlighted ? 0.95 : (selected == nil ? 0.45 : 0.12))), lineWidth: highlighted ? 2 : 1)
                    }
                }
                .allowsHitTesting(false)

                ForEach(graph.nodes) { node in
                    if let point = layout[node.id] {
                        nodeView(node, graph: graph)
                            .position(screen(point, in: geometry.size))
                    }
                }

                if graph.nodes.isEmpty {
                    ContentUnavailableView(
                        "No Notes Yet",
                        systemImage: "circle.hexagongrid",
                        description: Text("Create text notes and link them with [[double brackets]] to grow your graph.")
                    )
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                if let selected, let node = graph.nodes.first(where: { $0.id == selected }) {
                    infoCard(node, graph: graph)
                        .padding(16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Graph")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showsTags) { Label("Tags", systemImage: "number") }
                    .toggleStyle(.button)
                Toggle(isOn: $showsOrphans) { Label("Unlinked Notes", systemImage: "circle.dotted") }
                    .toggleStyle(.button)
                Button {
                    withAnimation(.snappy) {
                        offset = .zero
                        scale = 1
                    }
                } label: {
                    Label("Center", systemImage: "scope")
                }
            }
        }
        .task(id: graph.signature) {
            // Lay out off the main thread; animate dots to their places.
            let next = await Task.detached(priority: .userInitiated) {
                NoteGraph.forceLayout(nodes: graph.nodes.map(\.id), edges: graph.edges, start: layout)
            }.value
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { layout = next }
        }
    }

    // MARK: Pieces

    private func nodeView(_ node: NoteGraph.Node, graph: NoteGraph) -> some View {
        let isSelected = node.id == selected
        let isNeighbor = selected.map { graph.neighbors(of: $0).contains(node.id) } ?? false
        let dimmed = selected != nil && !isSelected && !isNeighbor
        let color: Color = node.isTag ? .teal : (node.isText ? .purple : .indigo)
        let size = node.isTag ? 10 : min(14 + CGFloat(graph.degree(of: node.id)) * 3, 34)
        return VStack(spacing: 4) {
            Circle()
                .fill(node.isTag ? Color.clear : color)
                .overlay(Circle().stroke(color, lineWidth: node.isTag ? 2 : 0))
                .frame(width: size, height: size)
                .shadow(color: color.opacity(dimmed ? 0 : 0.9), radius: isSelected ? 14 : 7)
                .scaleEffect(isSelected ? 1.3 : 1)
            if scale > 0.55 || isSelected || isNeighbor {
                Text(node.title)
                    .font(.caption.weight(isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 140)
            }
        }
        .opacity(dimmed ? 0.3 : 1)
        .animation(.snappy, value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                open(node)
            } else {
                withAnimation(.snappy) { selected = node.id }
            }
        }
    }

    private func infoCard(_ node: NoteGraph.Node, graph: NoteGraph) -> some View {
        HStack(spacing: 14) {
            Image(systemName: node.isTag ? "number" : (node.isText ? "doc.text" : "pencil.and.scribble"))
                .font(.title2)
                .foregroundStyle(node.isTag ? .teal : .purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title).font(.headline)
                Text("\(graph.degree(of: node.id)) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(node.isTag ? "Show Notes" : "Open") { open(node) }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .glowCard(node.isTag ? .teal : .purple)
    }

    private func open(_ node: NoteGraph.Node) {
        if node.isTag {
            navigation.openTag(node.title.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        } else if let id = UUID(uuidString: node.id) {
            navigation.openNote(id)
        }
    }

    private func screen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width + point.x * scale, y: size.height / 2 + offset.height + point.y * scale)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = panStart ?? offset
                panStart = start
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                }
            }
            .onEnded { _ in panStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let start = scaleStart ?? scale
                scaleStart = start
                scale = min(max(start * value, 0.2), 4)
            }
            .onEnded { _ in scaleStart = nil }
    }
}

/// Notes, tags and their links, read from the library's text index.
struct NoteGraph {
    struct Node: Identifiable {
        /// A note's UUID string, or "#tag" for a tag.
        let id: String
        let title: String
        let isText: Bool
        let isTag: Bool
    }

    struct Edge: Hashable {
        let from: String
        let to: String
        let isTag: Bool
    }

    let nodes: [Node]
    let edges: [Edge]

    @MainActor
    init(store: LibraryStore, showsTags: Bool, showsOrphans: Bool) {
        var edges: Set<Edge> = []
        for note in store.notes {
            for link in store.textIndex[note.id]?.links ?? [] {
                guard let target = store.note(titled: link.title), target.id != note.id else { continue }
                // One undirected line per pair.
                let ends = [note.id.uuidString, target.id.uuidString].sorted()
                edges.insert(Edge(from: ends[0], to: ends[1], isTag: false))
            }
            if showsTags {
                for tag in store.tags(of: note) {
                    edges.insert(Edge(from: note.id.uuidString, to: "#" + NoteLinks.key(tag), isTag: true))
                }
            }
        }
        let connected = Set(edges.flatMap { [$0.from, $0.to] })
        var nodes = store.notes
            .filter { showsOrphans || connected.contains($0.id.uuidString) }
            .map { Node(id: $0.id.uuidString, title: $0.title, isText: $0.isText, isTag: false) }
        if showsTags {
            var seen: Set<String> = []
            for tag in store.allTags where seen.insert(NoteLinks.key(tag)).inserted {
                nodes.append(Node(id: "#" + NoteLinks.key(tag), title: "#" + tag, isText: false, isTag: true))
            }
        }
        let ids = Set(nodes.map(\.id))
        self.nodes = nodes
        self.edges = edges.filter { ids.contains($0.from) && ids.contains($0.to) }.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    /// Changes whenever the graph's shape changes, to re-run the layout.
    var signature: String {
        nodes.map(\.id).joined(separator: ",") + "|" + edges.map { $0.from + ">" + $0.to }.joined(separator: ",")
    }

    func degree(of id: String) -> Int {
        edges.filter { $0.from == id || $0.to == id }.count
    }

    func neighbors(of id: String) -> Set<String> {
        Set(edges.compactMap { $0.from == id ? $0.to : ($0.to == id ? $0.from : nil) })
    }

    /// A small force-directed layout: nodes push apart, links pull together,
    /// and a weak pull keeps everything near the middle. Existing positions
    /// are kept as the starting point so the graph does not jump.
    static func forceLayout(nodes: [String], edges: [Edge], start: [String: CGPoint]) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        var positions: [CGPoint] = nodes.enumerated().map { index, id in
            if let point = start[id] { return point }
            let angle = Double(index) * 2.399963 // golden angle spreads new nodes evenly
            let radius = 30 * sqrt(Double(index + 1))
            return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element, $0.offset) })
        let links = edges.compactMap { edge -> (Int, Int)? in
            guard let a = index[edge.from], let b = index[edge.to] else { return nil }
            return (a, b)
        }
        let ideal: CGFloat = 110
        var temperature: CGFloat = 40
        let iterations = nodes.count > 300 ? 120 : 260
        for _ in 0..<iterations {
            var forces = [CGPoint](repeating: .zero, count: positions.count)
            for i in positions.indices {
                for j in positions.indices where j > i {
                    var dx = positions[i].x - positions[j].x
                    var dy = positions[i].y - positions[j].y
                    if dx == 0 && dy == 0 { dx = 0.1; dy = 0.1 }
                    let distanceSquared = max(dx * dx + dy * dy, 1)
                    let push = ideal * ideal / distanceSquared
                    forces[i].x += dx * push; forces[i].y += dy * push
                    forces[j].x -= dx * push; forces[j].y -= dy * push
                }
            }
            for (a, b) in links {
                let dx = positions[b].x - positions[a].x
                let dy = positions[b].y - positions[a].y
                let distance = max(sqrt(dx * dx + dy * dy), 1)
                let pull = distance / ideal
                forces[a].x += dx * pull * 0.5; forces[a].y += dy * pull * 0.5
                forces[b].x -= dx * pull * 0.5; forces[b].y -= dy * pull * 0.5
            }
            for i in positions.indices {
                forces[i].x -= positions[i].x * 0.02
                forces[i].y -= positions[i].y * 0.02
                let length = max(sqrt(forces[i].x * forces[i].x + forces[i].y * forces[i].y), 0.001)
                let step = min(length, temperature)
                positions[i].x += forces[i].x / length * step
                positions[i].y += forces[i].y / length * step
            }
            temperature = max(temperature * 0.97, 1)
        }
        return Dictionary(uniqueKeysWithValues: zip(nodes, positions))
    }
}
