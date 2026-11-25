import CoreGraphics
import Foundation
import PencilKit

/// A simple bucketed spatial index over stroke bounds. Viewport overlays ask
/// for the strokes intersecting a rect instead of scanning the whole note.
struct StrokeSpatialIndex {
    private let cellSize: CGFloat
    private var buckets: [String: [Int]] = [:]
    private var bounds: [Int: CGRect] = [:]

    init(strokes: [PKStroke], cellSize: CGFloat = 240) {
        self.cellSize = max(cellSize, 1)
        for (index, stroke) in strokes.enumerated() {
            let rect = stroke.renderBounds
            bounds[index] = rect
            for key in keys(for: rect) { buckets[key, default: []].append(index) }
        }
    }

    func intersecting(_ rect: CGRect) -> [Int] {
        var found = Set<Int>()
        for key in keys(for: rect) {
            if let list = buckets[key] {
                for index in list where bounds[index]?.intersects(rect) == true { found.insert(index) }
            }
        }
        return found.sorted()
    }

    private func keys(for rect: CGRect) -> [String] {
        let minX = Int(Math.roundDown(Double(rect.minX / cellSize)))
        let maxX = Int(Math.roundDown(Double(rect.maxX / cellSize)))
        let minY = Int(Math.roundDown(Double(rect.minY / cellSize)))
        let maxY = Int(Math.roundDown(Double(rect.maxY / cellSize)))
        var result: [String] = []
        for x in minX...maxX {
            for y in minY...maxY { result.append("\(x),\(y)") }
        }
        return result
    }
}
