import PencilKit
import SwiftUI

/// Settings for refining handwriting as you write (toolbar ✦ button).
struct HandwritingSettings: StoredLook {
    static let storageKey = "handwritingSettings"

    /// Smooths each stroke when the pencil lifts.
    var smooths = false
    /// 0 gentle ... 1 strong.
    var smoothStrength = 0.4
    /// Levels a slanted line of writing after a short pause.
    var straightens = false
    /// Evens out the size of words on that line, a little.
    var evensSize = false
    /// Seconds without writing before a line is straightened.
    var pause = 1.2

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        smooths = container.value(.smooths, or: smooths)
        smoothStrength = container.value(.smoothStrength, or: smoothStrength)
        straightens = container.value(.straightens, or: straightens)
        evensSize = container.value(.evensSize, or: evensSize)
        pause = container.value(.pause, or: pause)
    }

    var isActive: Bool { smooths || straightens || evensSize }
}

@MainActor
final class HandwritingSettingsStore: ObservableObject {
    static let shared = HandwritingSettingsStore()
    @Published var settings = HandwritingSettings.load() {
        didSet { settings.save() }
    }
}

/// Makes handwriting neater without changing what it says: smoother
/// strokes, level lines and more even word sizes.
enum HandwritingRefiner {
    // MARK: Smoothing

    /// The stroke with less wobble; its ends stay where they are.
    static func smooth(_ stroke: PKStroke, strength: Double) -> PKStroke {
        let path = stroke.path
        guard path.count >= 5 else { return stroke }
        var locations = path.map(\.location)
        let passes = 1 + Int((strength * 4).rounded())
        let weight = 0.35 + strength * 0.25
        for _ in 0..<passes {
            var next = locations
            for index in 1..<(locations.count - 1) {
                let previous = locations[index - 1]
                let following = locations[index + 1]
                let middle = CGPoint(x: (previous.x + following.x) / 2, y: (previous.y + following.y) / 2)
                next[index] = CGPoint(
                    x: locations[index].x + (middle.x - locations[index].x) * weight,
                    y: locations[index].y + (middle.y - locations[index].y) * weight
                )
            }
            locations = next
        }
        let points = zip(path, locations).map { point, location in
            PKStrokePoint(
                location: location, timeOffset: point.timeOffset, size: point.size,
                opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude
            )
        }
        var smoothed = stroke
        smoothed.path = PKStrokePath(controlPoints: points, creationDate: path.creationDate)
        return smoothed
    }

    // MARK: Lines

    /// Groups strokes into lines of writing. Strokes are followed left to
    /// right, so a slanted line stays one line.
    static func lines(of strokes: [Int: PKStroke]) -> [[Int]] {
        guard !strokes.isEmpty else { return [] }
        let heights = strokes.values.map(\.renderBounds.height).sorted()
        let typical = max(heights[heights.count / 2], 8)
        let sorted = strokes.sorted { $0.value.renderBounds.minX < $1.value.renderBounds.minX }
        var lines: [[Int]] = []
        var lastMid: [CGFloat] = []
        for (index, stroke) in sorted {
            let mid = stroke.renderBounds.midY
            if let nearest = lastMid.indices.min(by: { abs(lastMid[$0] - mid) < abs(lastMid[$1] - mid) }),
               abs(lastMid[nearest] - mid) < typical {
                lines[nearest].append(index)
                lastMid[nearest] = mid
            } else {
                lines.append([index])
                lastMid.append(mid)
            }
        }
        return lines
    }

    /// True when the strokes look like a line of words, not a drawing.
    static func looksLikeWriting(_ strokes: [PKStroke]) -> Bool {
        guard strokes.count >= 2 else { return false }
        let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        return bounds.width > bounds.height * 2.2 && bounds.height < 160
    }

    /// Levels a slanted line: finds its slope from the lowest points of each
    /// stroke and turns it flat around its middle.
    static func straighten(_ strokes: [PKStroke]) -> [PKStroke] {
        let bottoms = strokes.map { CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.maxY) }
        let centers = strokes.map { CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY) }
        // Average the slope through the bottoms and through the centers.
        guard let slopeA = slope(of: bottoms), let slopeB = slope(of: centers) else { return strokes }
        let angle = atan((slopeA + slopeB) / 2)
        let degrees = abs(angle * 180 / .pi)
        guard degrees > 1.5, degrees < 20 else { return strokes }
        let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let pivot = CGPoint(x: bounds.midX, y: bounds.midY)
        let turn = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: -angle))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        return strokes.map { stroke in
            var level = stroke
            level.transform = stroke.transform.concatenating(turn)
            return level
        }
    }

    /// Brings words that are much bigger or smaller than the others on the
    /// line closer to the usual size, keeping them on the same baseline.
    static func evenSize(_ strokes: [PKStroke]) -> [PKStroke] {
        let words = Self.words(in: strokes)
        guard words.count >= 2 else { return strokes }
        let heights = words.map { word in word.reduce(CGRect.null) { $0.union(strokes[$1].renderBounds) }.height }
        let typical = heights.sorted()[heights.count / 2]
        guard typical > 4 else { return strokes }
        var result = strokes
        for (word, height) in zip(words, heights) {
            let ratio = typical / max(height, 1)
            // Leave ordinary differences (tall letters, descenders) alone.
            guard ratio < 0.78 || ratio > 1.28 else { continue }
            let factor = min(max(ratio, 0.82), 1.2)
            let bounds = word.reduce(CGRect.null) { $0.union(strokes[$1].renderBounds) }
            let anchor = CGPoint(x: bounds.minX, y: bounds.maxY)
            let scale = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                .concatenating(CGAffineTransform(scaleX: factor, y: factor))
                .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
            for index in word {
                result[index].transform = strokes[index].transform.concatenating(scale)
            }
        }
        return result
    }

    /// Strokes grouped into words by the gaps between them.
    private static func words(in strokes: [PKStroke]) -> [[Int]] {
        let order = strokes.indices.sorted { strokes[$0].renderBounds.minX < strokes[$1].renderBounds.minX }
        let heights = strokes.map(\.renderBounds.height).sorted()
        let gap = max(heights[heights.count / 2] * 0.45, 6)
        var words: [[Int]] = []
        var current: [Int] = []
        var right: CGFloat = -.infinity
        for index in order {
            let bounds = strokes[index].renderBounds
            if current.isEmpty || bounds.minX - right < gap {
                current.append(index)
                right = max(right, bounds.maxX)
            } else {
                words.append(current)
                current = [index]
                right = bounds.maxX
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func slope(of points: [CGPoint]) -> CGFloat? {
        guard points.count >= 2 else { return nil }
        let count = CGFloat(points.count)
        let meanX = points.map(\.x).reduce(0, +) / count
        let meanY = points.map(\.y).reduce(0, +) / count
        let spread = points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        guard spread > 1 else { return nil }
        return points.map { ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +) / spread
    }

    /// Everything at once, for Refine on a lasso selection: smooth every
    /// stroke, then level and even out each line of writing.
    static func refine(_ strokes: [PKStroke], settings: HandwritingSettings) -> [PKStroke] {
        var result = strokes.map { $0.ink.inkType == .marker ? $0 : smooth($0, strength: max(settings.smoothStrength, 0.4)) }
        let indexed = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.offset, $0.element) })
        for line in lines(of: indexed) {
            let lineStrokes = line.map { result[$0] }
            guard looksLikeWriting(lineStrokes) else { continue }
            let refined = evenSize(straighten(lineStrokes))
            for (index, stroke) in zip(line, refined) {
                result[index] = stroke
            }
        }
        return result
    }
}

/// The toolbar popover for handwriting refinement.
struct HandwritingSettingsView: View {
    @ObservedObject private var store = HandwritingSettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Refine Handwriting")
                .font(.headline)
            Toggle(isOn: $store.settings.smooths) {
                Label("Smooth Strokes", systemImage: "scribble.variable")
            }
            if store.settings.smooths {
                LabeledSlider(title: "Smoothing", systemImage: "dial.medium", value: $store.settings.smoothStrength, range: 0...1,
                              text: store.settings.smoothStrength < 0.34 ? "Gentle" : store.settings.smoothStrength < 0.67 ? "Medium" : "Strong")
            }
            Toggle(isOn: $store.settings.straightens) {
                Label("Straighten Lines", systemImage: "text.alignleft")
            }
            Toggle(isOn: $store.settings.evensSize) {
                Label("Even Out Word Size", systemImage: "textformat.size")
            }
            if store.settings.straightens || store.settings.evensSize {
                LabeledSlider(title: "After a Pause Of", systemImage: "timer", value: $store.settings.pause, range: 0.6...3,
                              text: String(format: "%.1f s", store.settings.pause))
            }
            Divider()
            Text("Smoothing happens when you lift the pencil. Lines are leveled after you pause. Undo puts your writing back as it was. To refine writing already on the page, select it with the lasso and choose Refine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 320)
    }
}
