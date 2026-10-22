import SwiftUI

/// All mind maps, as glowing cards.
struct MindMapsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var path: [UUID] = []
    @State private var prompt: NamePrompt?
    @State private var mapToDelete: MindMap?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20)], spacing: 20) {
                    ForEach(workspace.mindMaps.sorted { $0.modifiedAt > $1.modifiedAt }) { map in
                        Button {
                            path.append(map.id)
                        } label: {
                            card(map)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                mapToDelete = map
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24)
            }
            .overlay {
                if workspace.mindMaps.isEmpty {
                    ContentUnavailableView(
                        "No Mind Maps",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Tap + to start a map from a central idea.")
                    )
                }
            }
            .navigationTitle("Mind Maps")
            .toolbar {
                Button {
                    prompt = NamePrompt(title: "New Mind Map", initialText: "", confirmTitle: "Create") { title in
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let map = MindMap(title: trimmed.isEmpty ? "Central Idea" : trimmed)
                        workspace.save(map)
                        path.append(map.id)
                    }
                } label: {
                    Label("New Mind Map", systemImage: "plus.circle.fill")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                MindMapEditor(mapID: id)
            }
            .namePrompt($prompt)
            .confirmationDialog(
                "Delete \"\(mapToDelete?.title ?? "")\"?",
                isPresented: Binding(get: { mapToDelete != nil }, set: { if !$0 { mapToDelete = nil } }),
                titleVisibility: .visible,
                presenting: mapToDelete
            ) { map in
                Button("Delete Mind Map", role: .destructive) { workspace.deleteMindMap(map.id) }
            }
        }
    }

    private func card(_ map: MindMap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MindMapPreview(map: map)
                .frame(height: 120)
            Text(map.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(map.nodes.count) ideas · \(map.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glowCard(.purple)
    }
}

/// A small drawing of a map's branches for its card.
private struct MindMapPreview: View {
    let map: MindMap

    var body: some View {
        Canvas { context, size in
            guard !map.nodes.isEmpty else { return }
            let xs = map.nodes.map { CGFloat($0.x) }
            let ys = map.nodes.map { CGFloat($0.y) }
            let minX: CGFloat = xs.min() ?? 0
            let maxX: CGFloat = xs.max() ?? 0
            let minY: CGFloat = ys.min() ?? 0
            let maxY: CGFloat = ys.max() ?? 0
            let scaleX: CGFloat = size.width / max(maxX - minX + 80, 1)
            let scaleY: CGFloat = size.height / max(maxY - minY + 40, 1)
            let scale = min(scaleX, scaleY)
            let midX = (minX + maxX) / 2
            let midY = (minY + maxY) / 2
            func point(_ node: MindNode) -> CGPoint {
                CGPoint(
                    x: size.width / 2 + (CGFloat(node.x) - midX) * scale,
                    y: size.height / 2 + (CGFloat(node.y) - midY) * scale
                )
            }
            let byID = Dictionary(map.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for node in map.nodes {
                guard let parent = node.parentID.flatMap({ byID[$0] }) else { continue }
                var path = Path()
                path.move(to: point(parent))
                path.addLine(to: point(node))
                context.stroke(path, with: .color(.purple.opacity(0.5)), lineWidth: 1.5)
            }
            for node in map.nodes {
                let center = point(node)
                let radius: CGFloat = node.parentID == nil ? 6 : 4
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(node.color?.color ?? .accentColor))
            }
        }
    }
}

/// Edits one mind map: pan and pinch the canvas, drag ideas (with their
/// branches), and add, rename, recolor or delete them from the bottom bar.
struct MindMapEditor: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let mapID: UUID

    @State private var map: MindMap?
    @State private var selectedID: UUID?
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat?
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var prompt: NamePrompt?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background: pan and zoom; tapping clears the selection.
                Color(uiColor: .systemBackground)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture)
                    .onTapGesture { withAnimation(.snappy) { selectedID = nil } }

                if let map {
                    connections(map, in: geometry.size)
                    ForEach(map.nodes) { node in
                        nodeView(node, in: map)
                            .position(screenPoint(node, in: geometry.size))
                    }
                }
            }
            .clipped()
        }
        .navigationTitle(map?.title ?? "Mind Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        map?.autoLayout()
                        offset = .zero
                    }
                    persist()
                } label: {
                    Label("Tidy Up", systemImage: "wand.and.stars")
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
        .safeAreaInset(edge: .bottom) {
            if let map, let selected = selectedID.flatMap({ id in map.nodes.first { $0.id == id } }) {
                actionBar(for: selected, in: map)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .namePrompt($prompt)
        .onAppear {
            if map == nil { map = workspace.mindMaps.first { $0.id == mapID } }
        }
    }

    // MARK: Drawing

    private func connections(_ map: MindMap, in size: CGSize) -> some View {
        Canvas { context, _ in
            let byID = Dictionary(map.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for node in map.nodes {
                guard let parent = node.parentID.flatMap({ byID[$0] }) else { continue }
                let start = screenPoint(parent, in: size)
                let end = screenPoint(node, in: size)
                let bend = (end.x - start.x) * 0.5
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: start.x + bend, y: start.y), control2: CGPoint(x: end.x - bend, y: end.y))
                let color = branchColor(node, in: map)
                // A wide faint stroke under a thin one gives the branch a glow.
                context.stroke(path, with: .color(color.opacity(0.25)), lineWidth: 8 * scale)
                context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 2.5 * scale)
            }
        }
        .allowsHitTesting(false)
    }

    private func nodeView(_ node: MindNode, in map: MindMap) -> some View {
        let isRoot = node.parentID == nil
        let isSelected = node.id == selectedID
        let color = branchColor(node, in: map)
        return Text(node.text.isEmpty ? "Idea" : node.text)
            .font(isRoot ? .title3.bold() : .body.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, isRoot ? 20 : 14)
            .padding(.vertical, isRoot ? 14 : 9)
            .frame(maxWidth: 220)
            .background(
                Capsule(style: .continuous)
                    .fill(isRoot ? color : color.opacity(0.18))
            )
            .foregroundStyle(isRoot ? Color.white : Color.primary)
            .overlay(Capsule(style: .continuous).stroke(color.opacity(isSelected ? 1 : 0.6), lineWidth: isSelected ? 3 : 1.5))
            .shadow(color: color.opacity(isSelected ? 0.9 : 0.4), radius: isSelected ? 16 : 8)
            .scaleEffect(scale * (isSelected && dragStart.isEmpty ? 1.06 : 1))
            .animation(dragStart.isEmpty ? .snappy : nil, value: isSelected)
            .onTapGesture(count: 2) { rename(node) }
            .onTapGesture { withAnimation(.snappy) { selectedID = node.id } }
            .gesture(dragGesture(for: node, in: map))
    }

    private func actionBar(for node: MindNode, in map: MindMap) -> some View {
        HStack(spacing: 6) {
            barButton("Add Idea", systemImage: "plus.bubble") { addChild(to: node) }
            if node.parentID != nil {
                barButton("Add Sibling", systemImage: "arrow.turn.down.right") { addSibling(of: node) }
            }
            barButton("Rename", systemImage: "pencil") { rename(node) }
            Menu {
                ForEach(FolderColor.allCases) { color in
                    Button {
                        update(node.id) { $0.color = color }
                    } label: {
                        Label(color.title, systemImage: node.color == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                barLabel("Color", systemImage: "paintpalette")
            }
            if node.parentID != nil {
                barButton("Delete", systemImage: "trash", role: .destructive) { delete(node) }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .glowCard(branchColor(node, in: map))
        .padding(.bottom, 12)
    }

    private func barButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            barLabel(title, systemImage: systemImage)
        }
        .buttonStyle(PressableStyle())
    }

    private func barLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: Gestures

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
                scale = min(max(start * value, 0.3), 3)
            }
            .onEnded { _ in scaleStart = nil }
    }

    /// Dragging an idea moves its whole branch.
    private func dragGesture(for node: MindNode, in map: MindMap) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // Follow the pencil exactly: no animation while dragging,
                // which otherwise leaves a trailing ghost of the idea.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                if dragStart.isEmpty {
                    withTransaction(transaction) { selectedID = node.id }
                    let ids = map.subtree(of: node.id)
                    for item in map.nodes where ids.contains(item.id) {
                        dragStart[item.id] = CGPoint(x: CGFloat(item.x), y: CGFloat(item.y))
                    }
                }
                let dx = value.translation.width / scale
                let dy = value.translation.height / scale
                guard var updated = self.map else { return }
                for index in updated.nodes.indices {
                    if let start = dragStart[updated.nodes[index].id] {
                        updated.nodes[index].x = Double(start.x + dx)
                        updated.nodes[index].y = Double(start.y + dy)
                    }
                }
                withTransaction(transaction) { self.map = updated }
            }
            .onEnded { _ in
                dragStart = [:]
                persist()
            }
    }

    // MARK: Editing

    private func addChild(to parent: MindNode) {
        guard let map else { return }
        let siblings = map.children(of: parent.id)
        let direction: Double = parent.parentID == nil || parent.x >= (map.root?.x ?? 0) ? 1 : -1
        let y = (siblings.map(\.y).max() ?? parent.y - 64) + 64
        let child = MindNode(text: "", parentID: parent.id, x: parent.x + 230 * direction, y: y)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            self.map?.nodes.append(child)
            selectedID = child.id
        }
        persist()
        rename(child)
    }

    private func addSibling(of node: MindNode) {
        guard let parentID = node.parentID, let parent = map?.nodes.first(where: { $0.id == parentID }) else { return }
        addChild(to: parent)
    }

    private func rename(_ node: MindNode) {
        prompt = NamePrompt(title: node.parentID == nil ? "Central Idea" : "Idea", initialText: node.text, confirmTitle: "Done") { text in
            update(node.id) { $0.text = text }
            if node.parentID == nil {
                map?.title = text.isEmpty ? (map?.title ?? "Mind Map") : text
                persist()
            }
        }
    }

    private func delete(_ node: MindNode) {
        guard let ids = map?.subtree(of: node.id) else { return }
        withAnimation(.snappy) {
            map?.nodes.removeAll { ids.contains($0.id) }
            selectedID = node.parentID
        }
        persist()
    }

    private func update(_ id: UUID, _ change: (inout MindNode) -> Void) {
        guard let index = map?.nodes.firstIndex(where: { $0.id == id }) else { return }
        change(&map!.nodes[index])
        persist()
    }

    private func persist() {
        if let map { workspace.save(map) }
    }

    // MARK: Geometry and colors

    private func screenPoint(_ node: MindNode, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + offset.width + CGFloat(node.x) * scale,
            y: size.height / 2 + offset.height + CGFloat(node.y) * scale
        )
    }

    /// A node's own color, else the color of the main branch it belongs to.
    private func branchColor(_ node: MindNode, in map: MindMap) -> Color {
        var current: MindNode? = node
        var steps = 0
        while let item = current, steps < map.nodes.count {
            if let color = item.color { return color.color }
            if item.parentID == map.root?.id {
                // Main branches get distinct colors in order.
                let palette: [Color] = [.blue, .orange, .green, .pink, .teal, .red, .indigo, .yellow]
                let index = map.children(of: map.root?.id ?? item.id).firstIndex { $0.id == item.id } ?? 0
                return palette[index % palette.count]
            }
            current = item.parentID.flatMap { id in map.nodes.first { $0.id == id } }
            steps += 1
        }
        return .purple
    }
}
