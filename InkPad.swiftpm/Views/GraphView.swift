import SwiftUI

/// Obsidian-style graph: every note as a dot, [[links]] as lines, and
/// optionally #tags as their own dots. Arrange it as a web, folder islands,
/// a timeline, rings around a note, a tree, a grid or by hand; restyle the
/// notes, lines and background. Pan, pinch, tap a note to see its links.
struct GraphView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.noteNavigation) private var navigation

    @AppStorage("graphShowsTags") private var showsTags = true
    @AppStorage("graphShowsOrphans") private var showsOrphans = true
    @State private var look = GraphLook.load()
    @State private var isCustomizing = false
    /// Where the force web put each note.
    @State private var webLayout: [String: CGPoint] = [:]
    @State private var layout: [String: CGPoint] = [:]
    @State private var guides: [GraphGuide] = []
    @State private var selected: String?
    @State private var dragging: (id: String, start: CGPoint)?
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat?

    private var currentGraph: NoteGraph {
        NoteGraph(store: store, showsTags: showsTags, showsOrphans: showsOrphans)
    }

    private static let palette: [Color] = [.purple, .blue, .teal, .green, .orange, .pink, .indigo, .mint, .red, .yellow]

    var body: some View {
        let graph = currentGraph
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture { withAnimation(.snappy) { selected = nil } }

                Canvas { context, size in
                    drawGuides(in: &context, size: size)
                    drawEdges(graph, in: &context, size: size)
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
        .screenBackdrop(look.backdrop)
        .navigationTitle("Graph")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Arrange", selection: $look.arrangement) {
                        ForEach(GraphLook.Arrangement.allCases) { arrangement in
                            Label(arrangement.title, systemImage: arrangement.systemImage).tag(arrangement)
                        }
                    }
                } label: {
                    Label("Arrange", systemImage: look.arrangement.systemImage)
                }
                Toggle(isOn: $showsTags) { Label("Tags", systemImage: "number") }
                    .toggleStyle(.button)
                Toggle(isOn: $showsOrphans) { Label("Unlinked Notes", systemImage: "circle.dotted") }
                    .toggleStyle(.button)
                Button {
                    isCustomizing = true
                } label: {
                    Label("Customize", systemImage: "paintbrush")
                }
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
        .sheet(isPresented: $isCustomizing) {
            GraphStyleView(look: $look)
        }
        .onChange(of: look) { look.save() }
        .onChange(of: look.arrangement) { rearrange(graph) }
        .onChange(of: selected) {
            if look.arrangement == .radial || look.arrangement == .tree, selected != nil { rearrange(graph) }
        }
        .task(id: graph.signature) {
            // Lay out the web off the main thread; animate dots to their places.
            let nodes = graph.nodes.map(\.id)
            let edges = graph.edges
            let start = webLayout.isEmpty ? layout : webLayout
            webLayout = await Task.detached(priority: .userInitiated) {
                NoteGraph.forceLayout(nodes: nodes, edges: edges, start: start)
            }.value
            rearrange(graph)
        }
    }

    private func rearrange(_ graph: NoteGraph) {
        let folderNames = Dictionary(uniqueKeysWithValues: store.folders.map { ($0.id, $0.name) })
        let arranged = graph.arrange(look.arrangement, focus: selected, folderNames: folderNames, manual: look.manual, current: webLayout)
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            layout = arranged.positions
            guides = arranged.guides
        }
    }

    // MARK: Drawing

    private func drawGuides(in context: inout GraphicsContext, size: CGSize) {
        for guide in guides {
            let center = screen(guide.center, in: size)
            let color = Self.palette[guide.colorIndex % Self.palette.count]
            switch guide.kind {
            case let .island(radius):
                let r = radius * scale
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color.opacity(0.18), color.opacity(0.04)]), center: center, startRadius: 0, endRadius: r))
                context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                context.draw(Text(guide.title).font(.headline).foregroundStyle(color), at: CGPoint(x: center.x, y: center.y - r - 12))
            case let .ring(radius):
                let r = radius * scale
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(Color.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                context.draw(Text(guide.title).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: center.x, y: center.y - r - 10))
            case let .axis(from, to):
                var line = Path()
                line.move(to: screen(CGPoint(x: from, y: 0), in: size))
                line.addLine(to: screen(CGPoint(x: to, y: 0), in: size))
                context.stroke(line, with: .color(Color.inkAccent.opacity(0.5)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .tick:
                var tick = Path()
                tick.move(to: CGPoint(x: center.x, y: center.y - 8))
                tick.addLine(to: CGPoint(x: center.x, y: center.y + 8))
                context.stroke(tick, with: .color(Color.inkAccent.opacity(0.7)), lineWidth: 2)
                context.draw(Text(guide.title).font(.caption.weight(.semibold)).foregroundStyle(Color.inkAccent), at: CGPoint(x: center.x, y: center.y + 22))
            }
        }
    }

    private func drawEdges(_ graph: NoteGraph, in context: inout GraphicsContext, size: CGSize) {
        for edge in graph.edges {
            guard let a = layout[edge.from], let b = layout[edge.to] else { continue }
            let highlighted = selected != nil && (edge.from == selected || edge.to == selected)
            let start = screen(a, in: size)
            let end = screen(b, in: size)
            var path = Path()
            path.move(to: start)
            if look.edgeStyle == .curved || look.arrangement == .timeline {
                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                let dx = end.x - start.x
                let dy = end.y - start.y
                // Timeline links arc above the axis; others bend to one side.
                let control = look.arrangement == .timeline
                    ? CGPoint(x: mid.x, y: min(start.y, end.y) - abs(dx) * 0.35 - 20)
                    : CGPoint(x: mid.x - dy * 0.2, y: mid.y + dx * 0.2)
                path.addQuadCurve(to: end, control: control)
            } else {
                path.addLine(to: end)
            }
            let color = edge.isTag ? Color.teal : edgeColor(edge)
            let dash: [CGFloat] = look.edgeStyle == .dashed ? [6, 5] : []
            if highlighted {
                context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 7)
            }
            context.stroke(
                path,
                with: .color(color.opacity(highlighted ? 0.95 : (selected == nil ? 0.45 : 0.12))),
                style: StrokeStyle(lineWidth: highlighted ? 2 : 1, lineCap: .round, dash: dash)
            )
        }
    }

    private func edgeColor(_ edge: NoteGraph.Edge) -> Color {
        look.colorBy == .kind ? .purple : Color.secondary
    }

    // MARK: Pieces

    private func color(of node: NoteGraph.Node) -> Color {
        if node.isTag { return .teal }
        switch look.colorBy {
        case .kind:
            return node.isText ? .purple : .indigo
        case .folder:
            guard let id = node.folderID, let folder = store.folder(id) else { return .gray }
            if let color = folder.color { return color.color }
            let index = store.folders.firstIndex { $0.id == id } ?? 0
            return Self.palette[index % Self.palette.count]
        case .age:
            // New notes warm, old notes cool.
            let days = max(Date().timeIntervalSince(node.date) / 86_400, 0)
            let warmth = max(0, 1 - log10(days + 1) / 3)
            return Color(hue: 0.62 - warmth * 0.55, saturation: 0.75, brightness: 0.95)
        }
    }

    @ViewBuilder
    private func nodeView(_ node: NoteGraph.Node, graph: NoteGraph) -> some View {
        let isSelected = node.id == selected
        let isNeighbor = selected.map { graph.neighbors(of: $0).contains(node.id) } ?? false
        let dimmed = selected != nil && !isSelected && !isNeighbor
        let tint = color(of: node)
        let degree = graph.degree(of: node.id)
        let grow = look.sizeByLinks ? CGFloat(degree) * 3 : 0
        let showsTitle = look.showsLabels && (scale > 0.55 || isSelected || isNeighbor)
        Group {
            switch look.nodeStyle {
            case .glow, .dot:
                let base: CGFloat = look.nodeStyle == .dot ? 8 : 14
                let size = node.isTag ? 10 : min(base + grow, 34)
                VStack(spacing: 4) {
                    Circle()
                        .fill(node.isTag ? Color.clear : tint)
                        .overlay(Circle().stroke(tint, lineWidth: node.isTag ? 2 : 0))
                        .frame(width: size, height: size)
                        .shadow(color: tint.opacity(dimmed || look.nodeStyle == .dot ? 0 : 0.9), radius: isSelected ? 14 : 7)
                    if showsTitle {
                        Text(node.title)
                            .font(.caption.weight(isSelected ? .bold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: 140)
                    }
                }
            case .bubble:
                let bubble: CGFloat = min(56 + grow * 2, 110)
                let size: CGFloat = node.isTag ? 44 : bubble
                Text(look.showsLabels ? node.title : "")
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(width: size, height: size)
                    .background(Circle().fill(tint.gradient))
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: tint.opacity(dimmed ? 0 : 0.5), radius: isSelected ? 12 : 5)
            case .card:
                HStack(spacing: 6) {
                    Image(systemName: node.isTag ? "number" : node.isText ? "doc.text" : "pencil.and.scribble")
                        .foregroundStyle(tint)
                    if look.showsLabels {
                        Text(node.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6 + grow / 4)
                .frame(maxWidth: 170)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tint.opacity(isSelected ? 1 : 0.5), lineWidth: isSelected ? 2 : 1))
                .shadow(color: tint.opacity(dimmed ? 0 : 0.35), radius: isSelected ? 10 : 4)
            }
        }
        .scaleEffect(isSelected ? 1.2 : 1)
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
        .gesture(dragGesture(for: node))
    }

    /// Dragging a note places it by hand (and switches to By Hand).
    private func dragGesture(for node: NoteGraph.Node) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard let point = layout[node.id] else { return }
                if dragging?.id != node.id { dragging = (node.id, point) }
                guard let start = dragging?.start else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    layout[node.id] = CGPoint(x: start.x + value.translation.width / scale, y: start.y + value.translation.height / scale)
                }
            }
            .onEnded { _ in
                dragging = nil
                if look.arrangement != .manual {
                    // Keep everything where it is now, then hand over.
                    look.manual = layout
                    guides = []
                    look.arrangement = .manual
                } else {
                    look.manual = layout
                }
            }
    }

    private func infoCard(_ node: NoteGraph.Node, graph: NoteGraph) -> some View {
        HStack(spacing: 14) {
            Image(systemName: node.isTag ? "number" : (node.isText ? "doc.text" : "pencil.and.scribble"))
                .font(.title2)
                .foregroundStyle(color(of: node))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title).font(.headline)
                Text("\(graph.degree(of: node.id)) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if look.arrangement != .radial && look.arrangement != .tree {
                Button {
                    look.arrangement = .radial
                } label: {
                    Label("Center", systemImage: "smallcircle.filled.circle")
                }
                .buttonStyle(.bordered)
            }
            Button(node.isTag ? "Show Notes" : "Open") { open(node) }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .glowCard(color(of: node))
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
        var folderID: UUID? = nil
        var date = Date.distantPast
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
        // Links accepted from Living Notes.
        for (a, b) in LivingNotes.shared.linkPairs where store.note(a) != nil && store.note(b) != nil {
            let ends = [a.uuidString, b.uuidString].sorted()
            edges.insert(Edge(from: ends[0], to: ends[1], isTag: false))
        }
        let connected = Set(edges.flatMap { [$0.from, $0.to] })
        var nodes = store.notes
            .filter { showsOrphans || connected.contains($0.id.uuidString) }
            .map { Node(id: $0.id.uuidString, title: $0.title, isText: $0.isText, isTag: false, folderID: $0.folderID, date: $0.createdAt) }
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
