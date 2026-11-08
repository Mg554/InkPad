import PDFKit
import SwiftUI

/// Turns a chapter (or any text) into a mind map or a graph of its
/// concepts, on the iPad, or with AI when asked (AI Firewall).
enum ChapterMaps {
    /// The concepts of a text, strongest first, without the title's own words.
    static func concepts(in text: String, excluding title: String, limit: Int) -> [String] {
        let result = LivingAnalyzer.analyze(text)
        let titleKey = LivingAnalyzer.key(for: title)
        // Two-word concepts ("tidal volume") count a little more than single words.
        func score(_ item: (key: String, value: Double)) -> Double {
            item.key.contains(" ") ? item.value * 1.5 : item.value
        }
        let ranked = result.terms.sorted { (a: (key: String, value: Double), b: (key: String, value: Double)) -> Bool in
            score(a) > score(b)
        }
        var names: [String] = []
        for (key, _) in ranked where key != titleKey && !titleKey.contains(key) {
            let name = result.displays[key] ?? key
            let lower = name.lowercased()
            // Skip "volume" once "tidal volume" is in, and the other way round.
            let overlaps = names.contains { chosen in
                let other = chosen.lowercased()
                return other == lower || other.contains(lower) || lower.contains(other)
            }
            if !overlaps { names.append(name) }
            if names.count >= limit { break }
        }
        return names
    }

    /// Sentences of a text, for finding concepts that appear together.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            if let sentence { result.append(sentence) }
        }
        return result
    }

    /// A mind map: the chapter in the middle, its sections (or main
    /// concepts) as branches, and the key concepts of each as leaves.
    static func mindMap(title: String, text: String, sections: [(title: String, text: String)]) -> MindMap {
        var map = MindMap(title: title)
        guard let rootID = map.root?.id else { return map }
        if !sections.isEmpty {
            for section in sections.prefix(9) {
                let branch = MindNode(text: section.title, parentID: rootID, x: 0, y: 0)
                map.nodes.append(branch)
                for concept in concepts(in: section.text, excluding: section.title, limit: 4) {
                    map.nodes.append(MindNode(text: concept, parentID: branch.id, x: 0, y: 0))
                }
            }
        } else {
            let main = concepts(in: text, excluding: title, limit: 6)
            let lines = sentences(in: text)
            var used: Set<String> = Set(main.map { $0.lowercased() })
            for concept in main {
                let branch = MindNode(text: concept, parentID: rootID, x: 0, y: 0)
                map.nodes.append(branch)
                // Leaves: what is said most often together with this concept.
                let nearby = lines.filter { $0.localizedCaseInsensitiveContains(concept) }.joined(separator: " ")
                for leaf in concepts(in: nearby, excluding: concept, limit: 6) where !used.contains(leaf.lowercased()) {
                    used.insert(leaf.lowercased())
                    map.nodes.append(MindNode(text: leaf, parentID: branch.id, x: 0, y: 0))
                    if map.children(of: branch.id).count >= 3 { break }
                }
            }
        }
        var style = MindMapStyle()
        style.layout = .radial
        style.branch = .organic
        style.shape = .rounded
        style.rootShape = .cloud
        map.style = style
        map.arrange(.radial, spacing: 1)
        return map
    }

    /// Asks the AI for the chapter's structure as a tree.
    static func mindMapWithAI(title: String, text: String, client: AIClient) async throws -> MindMap {
        let excerpt = String(text.prefix(14_000))
        let prompt = [
            "Make a study mind map of this book chapter, titled \"\(title)\".",
            "Use the chapter's own language. 4–8 main branches, each with 2–5 short sub-ideas (a few words each), and at most one more level where it really helps.",
            "Reply with JSON only: {\"title\": \"...\", \"children\": [{\"title\": \"...\", \"children\": [...]}]}",
            "Chapter text:",
            excerpt,
        ].joined(separator: "\n\n")
        let reply = try await client.complete(system: "You turn study material into clear mind maps. Reply with JSON only.", messages: [AIMessage(.user, prompt)])
        guard let json = AIJSON.object(in: reply) else { throw AIError.unreadable }
        let rootTitle = (json["title"] as? String) ?? title
        var map = MindMap(title: rootTitle)
        guard let rootID = map.root?.id else { return map }
        func add(_ items: Any?, under parent: UUID, depth: Int) {
            guard depth < 4, let list = items as? [[String: Any]] else { return }
            for item in list.prefix(10) {
                guard let text = item["title"] as? String, !text.isEmpty else { continue }
                let node = MindNode(text: text, parentID: parent, x: 0, y: 0)
                map.nodes.append(node)
                add(item["children"], under: node.id, depth: depth + 1)
            }
        }
        add(json["children"], under: rootID, depth: 0)
        guard map.nodes.count > 1 else { throw AIError.empty }
        var style = MindMapStyle()
        style.layout = .radial
        style.branch = .organic
        style.rootShape = .cloud
        map.style = style
        map.arrange(.radial, spacing: 1)
        return map
    }

    struct ConceptGraph {
        var concepts: [String]
        /// Pairs of concept indexes that appear in the same sentences, with how often.
        var links: [(Int, Int, Int)]
    }

    /// The chapter's main concepts and which ones appear together.
    static func conceptGraph(text: String, title: String, limit: Int = 24) -> ConceptGraph {
        let names = concepts(in: text, excluding: title, limit: limit)
        let lines = sentences(in: text)
        var counts: [String: Int] = [:]
        for line in lines {
            let present = names.indices.filter { line.localizedCaseInsensitiveContains(names[$0]) }
            guard present.count >= 2 else { continue }
            for i in present.indices {
                for j in present.indices where j > i {
                    counts["\(present[i])-\(present[j])", default: 0] += 1
                }
            }
        }
        let links: [(Int, Int, Int)] = counts.compactMap { key, count in
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, count >= 1 else { return nil }
            return (parts[0], parts[1], count)
        }
        .sorted { $0.2 > $1.2 }
        return ConceptGraph(concepts: names, links: Array(links.prefix(70)))
    }
}

/// A graph of a chapter's concepts: tap one to see where the book talks
/// about it, and jump there.
struct ConceptGraphView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let graph: ChapterMaps.ConceptGraph
    /// Pages (zero-based PDF pages) where a concept appears.
    let pagesFor: (String) -> [Int]
    let goToPage: (Int) -> Void

    @State private var positions: [String: CGPoint] = [:]
    @State private var selected: String?
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { selected = nil }
                        .gesture(MagnificationGesture()
                            .onChanged { value in
                                let start = scaleStart ?? scale
                                scaleStart = start
                                scale = min(max(start * value, 0.4), 3)
                            }
                            .onEnded { _ in scaleStart = nil })
                    Canvas { context, size in
                        for link in graph.links {
                            let a = graph.concepts[link.0]
                            let b = graph.concepts[link.1]
                            guard let p = positions[a], let q = positions[b] else { continue }
                            var path = Path()
                            path.move(to: screen(p, size))
                            path.addLine(to: screen(q, size))
                            let strong: Bool = selected == a || selected == b
                            let width: CGFloat = CGFloat(min(link.2, 6))
                            context.stroke(path, with: .color(Color.inkAccent.opacity(strong ? 0.8 : 0.25)), lineWidth: width)
                        }
                    }
                    .allowsHitTesting(false)
                    ForEach(graph.concepts, id: \.self) { concept in
                        if let point = positions[concept] {
                            chip(concept)
                                .position(screen(point, geometry.size))
                        }
                    }
                }
            }
            .themedBackground()
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    pagesBar(for: selected)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { layOut() }
        }
    }

    private func chip(_ concept: String) -> some View {
        let isSelected: Bool = selected == concept
        let fill: Color = Color.inkAccent.opacity(isSelected ? 0.3 : 0.12)
        return Text(concept)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(Color.inkAccent.opacity(0.5)))
            .onTapGesture { withAnimation(.snappy) { selected = concept } }
    }

    private func pagesBar(for concept: String) -> some View {
        let pages = pagesFor(concept)
        return VStack(alignment: .leading, spacing: 8) {
            Text("“\(concept)” is on \(pages.count) pages").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(pages.prefix(40), id: \.self) { page in
                        Button("p. \(page + 1)") {
                            dismiss()
                            goToPage(page)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func screen(_ point: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + point.x * scale, y: size.height / 2 + point.y * scale)
    }

    /// Moves the graph's middle to the center and fits it in about 700 points.
    private static func centered(_ points: [String: CGPoint]) -> [String: CGPoint] {
        guard !points.isEmpty else { return points }
        let xs = points.values.map(\.x)
        let ys = points.values.map(\.y)
        let minX: CGFloat = xs.min() ?? 0
        let maxX: CGFloat = xs.max() ?? 0
        let minY: CGFloat = ys.min() ?? 0
        let maxY: CGFloat = ys.max() ?? 0
        let midX: CGFloat = (minX + maxX) / 2
        let midY: CGFloat = (minY + maxY) / 2
        let span: CGFloat = max(maxX - minX, maxY - minY, 1)
        let fit: CGFloat = min(700 / span, 1.6)
        var result: [String: CGPoint] = [:]
        for (key, point) in points {
            result[key] = CGPoint(x: (point.x - midX) * fit, y: (point.y - midY) * fit)
        }
        return result
    }

    private func layOut() {
        let edges: [NoteGraph.Edge] = graph.links.map { link in
            NoteGraph.Edge(from: graph.concepts[link.0], to: graph.concepts[link.1], isTag: false)
        }
        let nodes = graph.concepts
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                NoteGraph.forceLayout(nodes: nodes, edges: edges, start: [:])
            }.value
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { positions = Self.centered(result) }
        }
    }
}
