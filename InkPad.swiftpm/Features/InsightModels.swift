import CoreGraphics
import Foundation
import ImageIO
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

/// Fills `{}` placeholders before the message goes through the app's Arabic
/// table. Note titles are never passed here.
private func trInsight(_ pattern: String, _ values: String...) -> String {
    var text = pattern
    for value in values {
        text = text.replacingOccurrences(of: "{}", with: value)
    }
    return trMessage(text)
}

// MARK: - Settings

/// One drawing a user saved for a Pencil Macro: a shape in a 0...1 box and
/// the command it stands for.
struct PencilMacro: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var action: MacroAction
    /// Resampled points of the shape, normalized into a unit square.
    var points: [CGPoint]
    let createdAt: Date

    init(name: String, action: MacroAction, points: [CGPoint]) {
        id = UUID()
        self.name = name
        self.action = action
        self.points = points
        createdAt = Date()
    }
}

enum MacroAction: String, CaseIterable, Codable, Identifiable {
    case task, beside, think, sticky, focus, ask

    var id: Self { self }

    var title: String {
        switch self {
        case .task: "Add a Planner Task"
        case .beside: "Open a Note Beside"
        case .think: "Think About This"
        case .sticky: "Add a Sticky Note"
        case .focus: "Start Focus Mode"
        case .ask: "Ask This Page"
        }
    }

    var symbol: String {
        switch self {
        case .task: "checklist"
        case .beside: "rectangle.split.2x1"
        case .think: "lightbulb"
        case .sticky: "note.text.badge.plus"
        case .focus: "scope"
        case .ask: "sparkles"
        }
    }
}

/// Settings for the new insight tools. Stored with `container.value(_:or:)`
/// so older settings files keep working when fields are added.
struct InsightSettings: StoredLook {
    static let storageKey = "insightSettings"

    var confidenceInk = true
    var frictionTracking = true
    var macros: [PencilMacro] = []
    var examMinutes = 20
    var postcardAuthor = ""
    /// Hides advanced panels during study; the page and tools stay.
    var _simpleMode = false
    var reviewRemindersOn = true
    var reviewHour = 9

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let box = try decoder.container(keyedBy: CodingKeys.self)
        confidenceInk = box.value(.confidenceInk, or: confidenceInk)
        frictionTracking = box.value(.frictionTracking, or: frictionTracking)
        macros = box.value(.macros, or: macros)
        examMinutes = box.value(.examMinutes, or: examMinutes)
        postcardAuthor = box.value(.postcardAuthor, or: postcardAuthor)
        _simpleMode = box.value(._simpleMode, or: _simpleMode)
        reviewRemindersOn = box.value(.reviewRemindersOn, or: reviewRemindersOn)
        reviewHour = box.value(.reviewHour, or: reviewHour)
    }
}

// MARK: - Writing Time-Lapse

/// One moment in the history of a page: every stroke written up to that
/// date, already rendered so playback never redraws ink.
struct TimelineFrame {
    let index: Int
    let date: Date
    let image: CGImage
    let strokeCount: Int
}

struct TimelineResult {
    let frames: [TimelineFrame]
    let first: Date
    let last: Date
    let strokeCount: Int

    var isEmpty: Bool { frames.isEmpty }
}

enum TimelineEngine {
    private struct Event {
        let date: Date
        var strokes: [PKStroke]
    }

    /// Builds a history from the creation date PencilKit keeps on every
    /// stroke. Eraser strokes are skipped: they hide ink rather than add it.
    static func build(drawing: PKDrawing, bounds: CGRect, maxFrames: Int = 60, scale: CGFloat = 1.2) -> TimelineResult {
        // PencilKit removes erased strokes from a saved drawing, so the
        // history is simply the strokes that remain, in the order written.
        let written = drawing.strokes
        let sorted = written.sorted { (a: PKStroke, b: PKStroke) -> Bool in
            a.path.creationDate < b.path.creationDate
        }
        guard let first = sorted.first?.path.creationDate,
              let last = sorted.last?.path.creationDate else {
            return TimelineResult(frames: [], first: Date(), last: Date(), strokeCount: 0)
        }
        var events: [Event] = []
        for stroke in sorted {
            let date = stroke.path.creationDate
            if let final = events.indices.last, events[final].date == date {
                events[final].strokes.append(stroke)
            } else {
                events.append(Event(date: date, strokes: [stroke]))
            }
        }
        let picked = sample(events, limit: max(2, maxFrames))
        var frames: [TimelineFrame] = []
        var cumulative: [PKStroke] = []
        for (index, event) in picked.enumerated() {
            cumulative.append(contentsOf: event.strokes)
            let partial = PKDrawing(strokes: cumulative)
            let picture = InkSnapshot.onWhite(of: partial, from: bounds, scale: scale)
            guard let cg = picture.cgImage else { continue }
            frames.append(TimelineFrame(index: index, date: event.date, image: cg, strokeCount: cumulative.count))
        }
        return TimelineResult(frames: frames, first: first, last: last, strokeCount: written.count)
    }

    /// Keeps evenly spaced moments so long notes never make hundreds of
    /// pictures. The last moment is always kept.
    private static func sample(_ events: [Event], limit: Int) -> [Event] {
        guard events.count > limit else { return events }
        var picked: [Event] = []
        var used = Set<Int>()
        let step = Double(events.count - 1) / Double(limit - 1)
        for position in 0..<limit {
            let index = min(Int((Double(position) * step).rounded()), events.count - 1)
            if used.insert(index).inserted { picked.append(events[index]) }
        }
        if picked.last?.date != events[events.count - 1].date {
            picked.append(events[events.count - 1])
        }
        return picked
    }

    /// Writes the frames as an animated GIF that can be shared from the iPad.
    static func writeGIF(_ result: TimelineResult, to url: URL) -> Bool {
        guard !result.frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.gif.identifier as CFString, result.frames.count, nil
              )
        else { return false }
        let loop: [String: Any] = [kCGImagePropertyGIFLoopCount as String: 0]
        let properties: [String: Any] = [kCGImagePropertyGIFDictionary as String: loop]
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        let delay: [String: Any] = [kCGImagePropertyGIFDelayTime as String: 0.14]
        let frameProperties: [String: Any] = [kCGImagePropertyGIFDictionary as String: delay]
        for frame in result.frames {
            CGImageDestinationAddImage(destination, frame.image, frameProperties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }
}

// MARK: - Confidence Ink

enum ConfidenceLevel: String, CaseIterable, Identifiable {
    case weak, learning, strong, unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .weak: "Forgetting"
        case .learning: "Still Learning"
        case .strong: "Remembered"
        case .unknown: "No Cards Yet"
        }
    }

    var symbol: String {
        switch self {
        case .weak: "exclamationmark.triangle.fill"
        case .learning: "circle.lefthalf.filled"
        case .strong: "checkmark.circle.fill"
        case .unknown: "circle.dashed"
        }
    }
}

struct ConfidenceMark: Identifiable {
    let id = UUID()
    let text: String
    let rect: CGRect
    let level: ConfidenceLevel
}

/// Colors a page's words by how well the matching flashcards are remembered.
/// Everything is worked out on the iPad from the cards' recall estimates.
enum ConfidenceEngine {
    @MainActor static func level(of text: String, workspace: WorkspaceStore) -> ConfidenceLevel {
        let words = Set(BookIndex.words(in: text))
        guard !words.isEmpty else { return .unknown }
        var recalls: [Double] = []
        for deck in workspace.flashcardDecks {
            for card in deck.cards {
                let cardWords = Set(BookIndex.words(in: card.front + " " + card.back))
                guard !cardWords.isDisjoint(with: words), let recall = card.recall() else { continue }
                recalls.append(recall)
            }
        }
        guard !recalls.isEmpty else { return .unknown }
        let total = recalls.reduce(0, +)
        let average = total / Double(recalls.count)
        if average < 0.5 { return .weak }
        if average < 0.8 { return .learning }
        return .strong
    }

    @MainActor static func marks(
        for lines: [(text: String, rect: CGRect)],
        workspace: WorkspaceStore
    ) -> [ConfidenceMark] {
        lines.compactMap { line in
            guard line.text.trimmingCharacters(in: .whitespacesAndNewlines).count > 2 else { return nil }
            return ConfidenceMark(text: line.text, rect: line.rect, level: level(of: line.text, workspace: workspace))
        }
    }

    static func summary(_ marks: [ConfidenceMark]) -> [(level: ConfidenceLevel, count: Int)] {
        ConfidenceLevel.allCases.compactMap { level in
            let count = marks.filter { $0.level == level }.count
            return count > 0 ? (level, count) : nil
        }
    }
}

// MARK: - Note Doctor

enum DoctorKind: String, CaseIterable, Identifiable {
    case stale, untagged, weakConcept, missingText, dueCards, orphanConcept

    var id: Self { self }

    var title: String {
        switch self {
        case .stale: "Not visited lately"
        case .untagged: "No tags yet"
        case .weakConcept: "Concept going cold"
        case .missingText: "Handwriting not read yet"
        case .dueCards: "Reviews waiting"
        case .orphanConcept: "Concept without cards"
        }
    }

    var symbol: String {
        switch self {
        case .stale: "clock.badge"
        case .untagged: "number"
        case .weakConcept: "heart.text.square"
        case .missingText: "text.badge.xmark"
        case .dueCards: "rectangle.on.rectangle.angled"
        case .orphanConcept: "lightbulb"
        }
    }
}

struct DoctorFinding: Identifiable {
    let id = UUID()
    let kind: DoctorKind
    let title: String
    let detail: String
    let noteID: UUID?
}

struct DoctorReport {
    let findings: [DoctorFinding]
    let generatedAt: Date

    @MainActor static func make(store: LibraryStore, workspace: WorkspaceStore) -> DoctorReport {
        var findings: [DoctorFinding] = []
        let now = Date()
        let month: TimeInterval = 45 * 86_400
        for note in store.notes where note.deletedAt == nil {
            if now.timeIntervalSince(note.modifiedAt) > month {
                findings.append(DoctorFinding(
                    kind: .stale, title: note.title,
                    detail: trInsight("Not edited in {} days.", String(format: "%.0f", now.timeIntervalSince(note.modifiedAt) / 86_400)),
                    noteID: note.id
                ))
            }
            if (note.tags ?? []).isEmpty {
                findings.append(DoctorFinding(
                    kind: .untagged, title: note.title,
                    detail: tr("A tag would let Smart Collections find it again."), noteID: note.id
                ))
            }
            if !note.isText, store.cachedRecognizedText(for: note.id) == nil, (note.hasAudio == true || note.pageCount ?? 0 > 0) {
                findings.append(DoctorFinding(
                    kind: .missingText, title: note.title,
                    detail: tr("Open this note once to read its handwriting on the iPad."), noteID: note.id
                ))
            }
            for concept in LivingNotes.shared.concepts(in: note.id).prefix(6) {
                var recalls: [Double] = []
                for deck in workspace.flashcardDecks {
                    for card in deck.cards where card.front.localizedCaseInsensitiveContains(concept.display)
                        || card.back.localizedCaseInsensitiveContains(concept.display) {
                        if let recall = card.recall() { recalls.append(recall) }
                    }
                }
                if let average = recalls.min(), average < 0.45 {
                    findings.append(DoctorFinding(
                        kind: .weakConcept, title: concept.display,
                        detail: trInsight("Weak in “{}”.", note.title), noteID: note.id
                    ))
                } else if recalls.isEmpty, concept.otherNotes == 0 {
                    findings.append(DoctorFinding(
                        kind: .orphanConcept, title: concept.display,
                        detail: trInsight("Only in “{}” and no flashcards yet.", note.title), noteID: note.id
                    ))
                }
            }
        }
        let due = workspace.flashcardDecks.reduce(0) { $0 + $1.dueCount }
        if due > 0 {
            findings.append(DoctorFinding(
                kind: .dueCards, title: tr("Flashcards are waiting"),
                detail: trInsight("{} cards are due for review.", String(due)), noteID: nil
            ))
        }
        return DoctorReport(findings: findings, generatedAt: now)
    }
}

// MARK: - Friction Map

struct FrictionPoint: Identifiable {
    let id = UUID()
    let page: Int
    let title: String
    let detail: String
    let date: Date
    /// Where on the page this happened, as 0…1 fractions (top-left origin).
    /// Pages from older builds have no position and are simply not drawn.
    var x: Double?
    var y: Double?

    var hasLocation: Bool { x != nil && y != nil }
}

struct FrictionReport {
    let pauses: Int
    let totalStrokes: Int
    let longestPause: TimeInterval
    let points: [FrictionPoint]

    var isEmpty: Bool { points.isEmpty }
}

/// Reads hesitation out of the ink itself: long pauses between strokes and
/// the same line written over and over. PencilKit deletes erased strokes, so
/// a pause or a rewrite is the evidence an erasure leaves behind.
enum FrictionEngine {
    static func make(drawing: PKDrawing, background: NoteBackground) -> FrictionReport {
        let rects = background.layout.pageRects
        let strokes = drawing.strokes
        let dated = strokes.sorted { $0.path.creationDate < $1.path.creationDate }
        var points: [FrictionPoint] = []
        var longest: TimeInterval = 0

        for index in 1..<max(dated.count, 1) {
            let previous = dated[index - 1]
            let current = dated[index]
            let gap = current.path.creationDate.timeIntervalSince(previous.path.creationDate)
            guard gap > 45, gap < 86_400 else { continue }
            longest = max(longest, gap)
            let pointPage = page(of: current, rects: rects)
            let spot = location(of: current, page: pointPage, rects: rects)
            points.append(FrictionPoint(
                page: pointPage,
                title: tr("A long pause here"),
                detail: trInsight("{} seconds before the next stroke.", String(format: "%.0f", gap)),
                date: current.path.creationDate,
                x: spot?.x, y: spot?.y
            ))
        }

        var bands: [Int: [(CGFloat, Date)]] = [:]
        for stroke in dated {
            let page = page(of: stroke, rects: rects)
            let key = page * 1000 + Int(stroke.renderBounds.midY / 40)
            bands[key, default: []].append((stroke.renderBounds.midX, stroke.path.creationDate))
        }
        for (key, samples) in bands where samples.count >= 4 {
            let xs = samples.map(\.0)
            guard let low = xs.min(), let high = xs.max(), high - low < 260 else { continue }
            let pointPage = key / 1000
            var spot: (x: Double, y: Double)?
            if rects.indices.contains(pointPage) {
                let rect = rects[pointPage]
                let midY = CGFloat(key % 1000) * 40 + 20
                spot = (
                    Double(((low + high) / 2) / max(rect.width, 1)),
                    Double(midY / max(rect.height, 1))
                )
            }
            points.append(FrictionPoint(
                page: pointPage,
                title: tr("Written over several times"),
                detail: trInsight("{} strokes close together on this line.", String(samples.count)),
                date: samples.last?.1 ?? Date(),
                x: spot?.x, y: spot?.y
            ))
        }
        return FrictionReport(
            pauses: points.count, totalStrokes: strokes.count,
            longestPause: longest, points: points.sorted { $0.date > $1.date }
        )
    }

    private static func page(of stroke: PKStroke, rects: [CGRect]) -> Int {
        rects.firstIndex { $0.contains(stroke.renderBounds.origin) } ?? 0
    }

    private static func location(of stroke: PKStroke, page: Int, rects: [CGRect]) -> (x: Double, y: Double)? {
        guard rects.indices.contains(page) else { return nil }
        let rect = rects[page]
        let bounds = stroke.renderBounds
        let midX = bounds.minX + bounds.width / 2
        let midY = bounds.minY + bounds.height / 2
        return (
            Double((midX - rect.minX) / max(rect.width, 1)),
            Double((midY - rect.minY) / max(rect.height, 1))
        )
    }
}

// MARK: - Pencil Macros

enum MacroEngine {
    /// Turns whatever the user drew into a comparable shape, independent of
    /// where on the page it was drawn and how big it is.
    static func normalize(_ drawing: PKDrawing) -> [CGPoint] {
        var raw: [CGPoint] = []
        for stroke in drawing.strokes {
            for point in stroke.path.interpolatedPoints(by: .distance(6)) {
                raw.append(point.location.applying(stroke.transform))
            }
        }
        guard let minX = raw.map(\.x).min(), let maxX = raw.map(\.x).max(),
              let minY = raw.map(\.y).min(), let maxY = raw.map(\.y).max() else { return [] }
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        return raw.map { CGPoint(x: ($0.x - minX) / width, y: ($0.y - minY) / height) }
    }

    static func match(_ drawing: PKDrawing, against macros: [PencilMacro]) -> PencilMacro? {
        let shape = resample(normalize(drawing), count: 32)
        guard shape.count == 32 else { return nil }
        var best: PencilMacro?
        var bestScore = 0.28
        for macro in macros {
            let candidate = resample(macro.points, count: 32)
            guard candidate.count == 32 else { continue }
            var sum = 0.0
            for index in 0..<32 {
                sum += Double(Math.distance(
                    shape[index].x - candidate[index].x,
                    shape[index].y - candidate[index].y
                ))
            }
            let score = sum / 32
            if score < bestScore {
                bestScore = score
                best = macro
            }
        }
        return best
    }

    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1, let first = points.first else { return [] }
        if points.count == 2 {
            return (0..<count).map { position in
                let t = CGFloat(position) / CGFloat(count - 1)
                return CGPoint(x: first.x + (points[1].x - first.x) * t,
                               y: first.y + (points[1].y - first.y) * t)
            }
        }
        var lengths: [CGFloat] = [0]
        for index in 1..<points.count {
            let dx = points[index].x - points[index - 1].x
            let dy = points[index].y - points[index - 1].y
            lengths.append(lengths[index - 1] + Math.distance(dx, dy))
        }
        guard let total = lengths.last, total > 0 else { return Array(repeating: first, count: count) }
        var result: [CGPoint] = []
        var cursor = 1
        for position in 0..<count {
            let target = total * CGFloat(position) / CGFloat(count - 1)
            while cursor < lengths.count - 1, lengths[cursor] < target { cursor += 1 }
            let span = lengths[cursor] - lengths[cursor - 1]
            let t = span > 0 ? (target - lengths[cursor - 1]) / span : 0
            result.append(CGPoint(
                x: points[cursor - 1].x + (points[cursor].x - points[cursor - 1].x) * t,
                y: points[cursor - 1].y + (points[cursor].y - points[cursor - 1].y) * t
            ))
        }
        return result
    }
}

// MARK: - Future-Me Marginalia

struct MarginalQuestion: Codable, Identifiable, Equatable {
    let id: UUID
    let noteID: UUID
    let text: String
    let due: Date
    var answeredAt: Date?
    var answer: String?

    init(noteID: UUID, text: String, due: Date) {
        id = UUID()
        self.noteID = noteID
        self.text = text
        self.due = due
    }
}

// MARK: - Offline Postcards

/// A note left for another copy of InkPad through the free sync folder.
/// No account, no server: iCloud Drive moves the JSON file.
struct Postcard: Codable, Identifiable, Equatable {
    let id: UUID
    let noteID: UUID
    let page: Int
    var text: String
    let author: String
    let date: Date
}

@MainActor
final class PostcardStore: ObservableObject {
    static let shared = PostcardStore()

    @Published private(set) var cards: [Postcard] = []
    @Published private(set) var problem: String?

    private func inFolder<T>(_ work: (URL) -> T?) -> T? {
        guard let folder = try? SyncEngine.shared.postcardsURL() else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return work(folder)
    }

    func refresh() {
        let found = inFolder { folder -> [Postcard]? in
            let url = folder.appendingPathComponent("postcards.json")
            guard let data = try? Data(contentsOf: url) else { return [] }
            return try? JSONDecoder().decode([Postcard].self, from: data)
        }
        guard let found else {
            cards = []
            problem = tr("Turn on Sync and choose a folder in iCloud Drive first.")
            return
        }
        problem = nil
        cards = found.sorted { $0.date > $1.date }
    }

    func send(noteID: UUID, page: Int, text: String, author: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let card = Postcard(
            id: UUID(), noteID: noteID, page: page, text: trimmed,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SyncEngine.shared.deviceName : author,
            date: Date()
        )
        let saved = inFolder { folder -> Bool in
            let url = folder.appendingPathComponent("postcards.json")
            var all: [Postcard] = []
            if let data = try? Data(contentsOf: url),
               let existing = try? JSONDecoder().decode([Postcard].self, from: data) {
                all = existing
            }
            guard !all.contains(where: { $0.id == card.id }) else { return true }
            all.append(card)
            guard let data = try? JSONEncoder().encode(all) else { return false }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        if saved != true {
            problem = tr("The postcard could not be saved. Check the sync folder in Settings.")
        }
        refresh()
    }
}

// MARK: - Cross-Note Debate

struct DebatePoint: Identifiable {
    let id = UUID()
    let noteID: UUID?
    let text: String
}

enum DebateEngine {
    /// Asks the connected AI to find disagreements between two notes. Only
    /// text the AI Firewall allows is put in the prompt.
    static func compare(sources: [StudySource], client: AIClient) async throws -> [DebatePoint] {
        guard sources.count >= 2 else { return [] }
        let first = sources[0]
        let second = sources[1]
        let prompt = [
            "Two study notes are about the same subject. List only real disagreements or contradictions between them, at most six.",
            "Write one short point per line, starting with A if it comes from the first note or B if it comes from the second.",
            "If they agree on everything, write one line: They agree.",
            "",
            "=== \(first.title) ===",
            String(first.text.prefix(6000)),
            "",
            "=== \(second.title) ===",
            String(second.text.prefix(6000)),
        ].joined(separator: "\n")
        let reply = try await client.complete(
            system: "You find contradictions in study notes, never adding outside facts.",
            messages: [AIMessage(.user, prompt)]
        )
        return reply.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " -•\t"))
            guard !line.isEmpty, line != "They agree." else { return nil }
            if line.hasPrefix("A:") || line.hasPrefix("A -") {
                return DebatePoint(noteID: first.id, text: String(line.dropFirst(2)))
            }
            if line.hasPrefix("B:") || line.hasPrefix("B -") {
                return DebatePoint(noteID: second.id, text: String(line.dropFirst(2)))
            }
            return DebatePoint(noteID: nil, text: line)
        }
    }
}

// MARK: - Exam Mode

/// A timed, closed-book session. It runs on the note screen and closes the
/// places where notes or AI could give an answer away.
@MainActor
final class ExamSession: ObservableObject {
    static let shared = ExamSession()

    @Published private(set) var isActive = false
    @Published private(set) var noteID: UUID?
    @Published private(set) var title = ""
    @Published private(set) var endsAt = Date()
    @Published private(set) var remaining = 0
    @Published private(set) var didTimeOut = false
    private var timer: Timer?

    func start(noteID: UUID, title: String, minutes: Int) {
        guard !isActive else { return }
        self.noteID = noteID
        self.title = title
        let seconds = max(1, minutes) * 60
        remaining = seconds
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        didTimeOut = false
        isActive = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard isActive else { return }
        let left = Int(endsAt.timeIntervalSince(Date()).rounded(.up))
        remaining = max(left, 0)
        if left <= 0 {
            didTimeOut = true
            finish()
        }
    }

    func finish() {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        isActive = false
    }
}
