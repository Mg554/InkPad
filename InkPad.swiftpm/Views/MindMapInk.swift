import PencilKit
import SwiftUI
import Vision

/// A PencilKit canvas with Apple's tool picker.
struct InkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var contentSize: CGSize?
    var showsToolPicker = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        if let contentSize {
            canvas.contentSize = contentSize
            canvas.minimumZoomScale = 0.4
            canvas.maximumZoomScale = 2.5
            // Start in the middle of the big sheet.
            DispatchQueue.main.async {
                canvas.contentOffset = CGPoint(
                    x: max((contentSize.width - canvas.bounds.width) / 2, 0),
                    y: max((contentSize.height - canvas.bounds.height) / 2, 0)
                )
            }
        }
        if showsToolPicker {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvas)
            context.coordinator.toolPicker.addObserver(canvas)
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: InkCanvas
        let toolPicker = PKToolPicker()

        init(_ parent: InkCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

/// Write an idea by hand. The writing shows on the map; its text is read
/// on the iPad for search and for the map's title.
struct HandwrittenIdeaEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: Data?
    let save: (Data?, String) -> Void
    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                InkCanvas(drawing: $drawing)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                    .frame(height: 280)
                Text("Write the idea with Apple Pencil. It stays in your handwriting on the map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Write by Hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Use Typing") {
                        save(nil, "")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let data = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
                        save(data, MindSketchReader.readText(drawing))
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let initial, let saved = try? PKDrawing(data: initial) { drawing = saved }
            }
        }
    }
}

/// Sketch a whole map freely, then Reshape turns it into a tidy map.
struct MindSketchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared
    let initial: Data?
    let style: MindMapStyle
    /// The ideas found, and the sketch to keep.
    let finish: (MindSketchReader.Result, MindMapStyle.Layout, Bool, Data) -> Void

    @State private var drawing = PKDrawing()
    @State private var isChoosing = false
    @State private var layout = MindMapStyle.Layout.radial
    @State private var keepsHandwriting = true
    @State private var usesAI = false
    @State private var isWorking = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            InkCanvas(drawing: $drawing, contentSize: CGSize(width: 2400, height: 1800))
                .background(Color(uiColor: .systemBackground))
                .overlay(alignment: .top) {
                    if drawing.strokes.isEmpty {
                        Text("Write your central idea, ideas around it, and draw lines to link them. Then tap Reshape.")
                            .font(.callout)
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if isWorking {
                        ProgressView("Reading your sketch…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .navigationTitle("Sketch a Map")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") { drawing = PKDrawing() }
                            .disabled(drawing.strokes.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            isChoosing = true
                        } label: {
                            Label("Reshape…", systemImage: "wand.and.stars")
                        }
                        .disabled(drawing.strokes.isEmpty || isWorking)
                    }
                }
                .sheet(isPresented: $isChoosing) { reshapeOptions }
                .alert("Reshape", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(problem ?? "")
                }
        }
        .onAppear {
            if let initial, let saved = try? PKDrawing(data: initial) { drawing = saved }
            layout = style.layout == .free ? .radial : style.layout
        }
    }

    private var reshapeOptions: some View {
        NavigationStack {
            Form {
                Section("Shape") {
                    Picker("Layout", selection: $layout) {
                        ForEach(MindMapStyle.Layout.allCases) { layout in
                            Label(tr(layout.title), systemImage: layout.systemImage).tag(layout)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle(isOn: $keepsHandwriting) {
                        Label("Keep My Handwriting", systemImage: "signature")
                    }
                    Toggle(isOn: $usesAI) {
                        Label("Let AI Organize It", systemImage: "sparkles")
                    }
                    .disabled(ai.problem != nil)
                } footer: {
                    if let problem = ai.problem {
                        Text("AI: \(problem)")
                    } else {
                        Text("Your writing is read on this iPad. With Let AI Organize It, only the words of your ideas are sent to \(ai.provider.title), which decides which idea belongs under which and fixes misread words. Without it, the lines you drew decide.")
                    }
                }
            }
            .navigationTitle("Reshape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isChoosing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reshape") {
                        isChoosing = false
                        reshape()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func reshape() {
        isWorking = true
        let drawing = drawing
        let client = usesAI ? ai.client() : nil
        Task {
            defer { isWorking = false }
            var result = await Task.detached(priority: .userInitiated) {
                MindSketchReader.read(drawing)
            }.value
            guard !result.ideas.isEmpty else {
                problem = "No writing was found. Write each idea clearly, with some space between ideas."
                return
            }
            if let client {
                do {
                    result = try await MindSketchReader.organizeWithAI(result, client: client)
                } catch {
                    problem = "AI couldn't organize it (\(error.localizedDescription)), so the lines you drew were used."
                }
            }
            finish(result, layout, keepsHandwriting, drawing.dataRepresentation())
            if problem == nil { dismiss() }
        }
    }
}

/// Reads a freehand mind map sketch: the writing becomes ideas, and lines
/// drawn between them become branches.
enum MindSketchReader {
    struct Idea {
        var text: String
        var rect: CGRect
        var strokes: [PKStroke] = []
    }

    struct Result {
        var ideas: [Idea]
        /// The parent of each idea; `nil` for the central idea.
        var parents: [Int?]
    }

    static func readText(_ drawing: PKDrawing) -> String {
        lines(in: drawing).map(\.text).joined(separator: " ")
    }

    /// Lines of writing with where they are on the drawing.
    private static func lines(in drawing: PKDrawing) -> [Idea] {
        let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)
        guard !drawing.strokes.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
        let scale: CGFloat = min(2, 4000 / max(bounds.width, bounds.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let ink = InkSnapshot.snapshot(of: drawing, from: bounds, scale: scale)
        let picture = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            ink.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
        guard let cgImage = picture.cgImage else { return [] }
        return InkOCR.lines(in: cgImage, mappedTo: bounds).map { Idea(text: $0.text, rect: $0.rect) }
    }

    static func read(_ drawing: PKDrawing) -> Result {
        var ideas = merge(lines(in: drawing))
        guard !ideas.isEmpty else { return Result(ideas: [], parents: []) }

        // Strokes inside an idea's writing belong to it; the rest are lines.
        var connectors: [[CGPoint]] = []
        for stroke in drawing.strokes {
            let box = stroke.renderBounds
            let area = max(box.width * box.height, 1)
            let owner = ideas.indices.max { a, b in
                overlap(box, ideas[a].rect.insetBy(dx: -8, dy: -8)) < overlap(box, ideas[b].rect.insetBy(dx: -8, dy: -8))
            }
            if let owner, overlap(box, ideas[owner].rect.insetBy(dx: -8, dy: -8)) / area > 0.55 {
                ideas[owner].strokes.append(stroke)
            } else {
                let points = ShapeRecognizer.points(of: stroke)
                if isOutline(points, around: ideas) { continue }
                connectors.append(points)
            }
        }

        // A line whose two ends are near two ideas links them.
        var links: Set<[Int]> = []
        for points in connectors {
            guard let first = points.first, let last = points.last,
                  let a = nearest(first, in: ideas, within: 90),
                  let b = nearest(last, in: ideas, within: 90), a != b
            else { continue }
            links.insert([min(a, b), max(a, b)])
        }
        let parents = tree(ideas: ideas, links: links.map { ($0[0], $0[1]) })
        return Result(ideas: ideas, parents: parents)
    }

    /// Joins lines that are one idea written on two or three lines.
    private static func merge(_ lines: [Idea]) -> [Idea] {
        var ideas = lines.sorted { $0.rect.minY < $1.rect.minY }
        var merged = true
        while merged {
            merged = false
            outer: for i in ideas.indices {
                for j in ideas.indices where j > i {
                    let a = ideas[i].rect
                    let b = ideas[j].rect
                    let gap = max(b.minY - a.maxY, a.minY - b.maxY)
                    let horizontal = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
                    if gap < min(a.height, b.height) * 0.6, horizontal > min(a.width, b.width) * 0.4 {
                        let top = a.minY <= b.minY ? ideas[i] : ideas[j]
                        let bottom = a.minY <= b.minY ? ideas[j] : ideas[i]
                        ideas[i] = Idea(text: top.text + " " + bottom.text, rect: a.union(b))
                        ideas.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return ideas
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let both = a.intersection(b)
        return both.isNull ? 0 : both.width * both.height
    }

    /// A closed loop drawn around one idea (a bubble), not a link.
    private static func isOutline(_ points: [CGPoint], around ideas: [Idea]) -> Bool {
        guard let first = points.first, let last = points.last, points.count > 8 else { return false }
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let closed = Math.distance(first.x - last.x, first.y - last.y) < max(box.width, box.height) * 0.3
        return closed && ideas.contains { box.insetBy(dx: -10, dy: -10).contains($0.rect.insetBy(dx: $0.rect.width * 0.2, dy: $0.rect.height * 0.2)) }
    }

    private static func nearest(_ point: CGPoint, in ideas: [Idea], within limit: CGFloat) -> Int? {
        let distances = ideas.map { distance(point, to: $0.rect) }
        guard let best = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[best] <= limit else { return nil }
        return best
    }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return Math.distance(dx, dy)
    }

    private static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// The central idea is the most linked one (or the biggest writing);
    /// branches follow the links, and unlinked ideas join the nearest one.
    private static func tree(ideas: [Idea], links: [(Int, Int)]) -> [Int?] {
        var neighbors: [Int: [Int]] = [:]
        for (a, b) in links {
            neighbors[a, default: []].append(b)
            neighbors[b, default: []].append(a)
        }
        let root = ideas.indices.max { a, b in
            let la = neighbors[a]?.count ?? 0
            let lb = neighbors[b]?.count ?? 0
            return la != lb ? la < lb : ideas[a].rect.height < ideas[b].rect.height
        } ?? 0
        var parents = [Int?](repeating: nil, count: ideas.count)
        var placed: Set<Int> = [root]
        var queue = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for next in neighbors[current] ?? [] where !placed.contains(next) {
                parents[next] = current
                placed.insert(next)
                queue.append(next)
            }
        }
        // Unlinked ideas hang from the closest placed idea.
        while placed.count < ideas.count {
            var best: (idea: Int, parent: Int, distance: CGFloat)?
            for idea in ideas.indices where !placed.contains(idea) {
                for parent in placed {
                    let a = center(ideas[idea].rect)
                    let b = center(ideas[parent].rect)
                    let d = Math.distance(a.x - b.x, a.y - b.y)
                    if best == nil || d < best!.distance { best = (idea, parent, d) }
                }
            }
            guard let best else { break }
            parents[best.idea] = best.parent
            placed.insert(best.idea)
        }
        return parents
    }

    /// Asks the AI which idea belongs under which (and to fix misread words).
    /// Only the ideas' words are sent.
    static func organizeWithAI(_ result: Result, client: AIClient) async throws -> Result {
        let list = result.ideas.enumerated().map { "\($0.offset): \($0.element.text)" }.joined(separator: "\n")
        let drawn = result.parents.enumerated().compactMap { index, parent in parent.map { "\(index) under \($0)" } }.joined(separator: ", ")
        let prompt = [
            "These are the ideas of a hand-drawn mind map, read from handwriting (some words may be misread):",
            list,
            "The lines the person drew suggest: \(drawn.isEmpty ? "none" : drawn).",
            "Organize them into one clear mind map tree. Keep every idea; fix obviously misread words but don't add new ideas.",
            "Reply with JSON only: {\"parents\": [..], \"texts\": [..]}, where parents[i] is the number of idea i's parent, or -1 for the single central idea, and texts[i] is idea i's corrected text.",
        ].joined(separator: "\n\n")
        let reply = try await client.complete(system: "You organize mind maps. Reply with JSON only.", messages: [AIMessage(.user, prompt)])
        guard let json = AIJSON.object(in: reply), let raw = json["parents"] as? [Any], raw.count == result.ideas.count else {
            throw AIError.unreadable
        }
        let parents: [Int?] = raw.map { value in
            let number = (value as? Int) ?? (value as? NSNumber)?.intValue ?? -1
            return number < 0 || number >= result.ideas.count ? nil : number
        }
        // Exactly one root and no loops, or keep the drawn shape.
        guard parents.filter({ $0 == nil }).count == 1, !hasLoop(parents) else { throw AIError.unreadable }
        var organized = result
        organized.parents = parents
        if let texts = json["texts"] as? [String], texts.count == result.ideas.count {
            for index in texts.indices where !texts[index].trimmingCharacters(in: .whitespaces).isEmpty {
                organized.ideas[index].text = texts[index]
            }
        }
        return organized
    }

    private static func hasLoop(_ parents: [Int?]) -> Bool {
        for start in parents.indices {
            var seen: Set<Int> = [start]
            var current = parents[start]
            while let next = current {
                if !seen.insert(next).inserted { return true }
                current = parents[next]
            }
        }
        return false
    }
}

extension MindMap {
    /// Replaces the ideas with ones read from a sketch.
    mutating func adopt(_ result: MindSketchReader.Result, layout: MindMapStyle.Layout, keepsHandwriting: Bool) {
        guard let rootIndex = result.parents.firstIndex(where: { $0 == nil }) else { return }
        let origin = CGPoint(x: result.ideas[rootIndex].rect.midX, y: result.ideas[rootIndex].rect.midY)
        var made: [MindNode] = result.ideas.enumerated().map { index, idea in
            MindNode(
                text: idea.text,
                parentID: nil,
                x: Double(idea.rect.midX - origin.x),
                y: Double(idea.rect.midY - origin.y),
                color: index == rootIndex ? .purple : nil
            )
        }
        for (index, idea) in result.ideas.enumerated() {
            made[index].parentID = result.parents[index].map { made[$0].id }
            if keepsHandwriting, !idea.strokes.isEmpty {
                let box = idea.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
                let shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
                let moved = idea.strokes.map { stroke -> PKStroke in
                    var copy = stroke
                    copy.transform = stroke.transform.concatenating(shift)
                    return copy
                }
                made[index].ink = PKDrawing(strokes: moved).dataRepresentation()
            }
        }
        // The central idea first, as the map expects.
        made.sort { a, b in a.parentID == nil && b.parentID != nil }
        nodes = made
        title = result.ideas[rootIndex].text
        var style = appliedStyle
        style.layout = layout
        self.style = style
        arrange(layout, spacing: style.spacing)
        modifiedAt = Date()
    }
}
