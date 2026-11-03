import SwiftUI

/// Notability-style size bar with levels 1...20. Drag or tap along it: the
/// width follows the pencil smoothly, the number shows the nearest level,
/// and each level passed gives a light tick.
struct WidthLevelBar: View {
    static let levels = 20

    /// Where the handle is, from 0 (thinnest) to 1 (thickest).
    @Binding private var position: CGFloat
    /// Lands on whole levels (for selected ink, which is resized step by step).
    private let snaps: Bool

    /// Moves smoothly between levels.
    init(position: Binding<CGFloat>) {
        _position = position
        snaps = false
    }

    /// Moves level by level.
    init(level: Binding<Int>) {
        _position = Binding(
            get: { Self.position(forLevel: level.wrappedValue) },
            set: { level.wrappedValue = Self.level(atPosition: $0) }
        )
        snaps = true
    }

    private var currentLevel: Int { Self.level(atPosition: position) }

    var body: some View {
        GeometryReader { geometry in
            let levels = Self.levels
            let barWidth = geometry.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(1...levels, id: \.self) { step in
                        Capsule()
                            .fill(step <= currentLevel ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: 5 + CGFloat(step) * 0.6)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 30)
                Text("\(currentLevel)")
                    .font(.caption.bold().monospacedDigit())
                    .frame(width: 34, height: 34)
                    .background(.background, in: Circle())
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: .accentColor.opacity(0.5), radius: 6)
                    .offset(x: position * (barWidth - 34))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var next = min(max((value.location.x - 17) / max(barWidth - 34, 1), 0), 1)
                        if snaps {
                            next = Self.position(forLevel: Self.level(atPosition: next))
                        }
                        if abs(next - position) > 0.0005 { position = next }
                    }
            )
        }
        .frame(height: 40)
        .sensoryFeedback(.selection, trigger: currentLevel)
    }

    // MARK: Scale

    static func position(forLevel level: Int) -> CGFloat {
        CGFloat(min(max(level, 1), levels) - 1) / CGFloat(levels - 1)
    }

    static func level(atPosition position: CGFloat) -> Int {
        1 + Int((min(max(position, 0), 1) * CGFloat(levels - 1)).rounded())
    }

    /// The width at a handle position. Each step along the bar multiplies the
    /// width by the same amount, so the size changes evenly from end to end:
    /// a straight scale grows thin pens in big jumps and barely changes thick
    /// ones.
    static func width(atPosition position: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let fraction = min(max(position, 0), 1)
        guard range.lowerBound > 0, range.upperBound > range.lowerBound else {
            return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
        }
        return range.lowerBound * pow(range.upperBound / range.lowerBound, fraction)
    }

    static func position(forWidth width: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        let fraction: CGFloat
        if range.lowerBound > 0, range.upperBound > range.lowerBound {
            fraction = log(max(width, range.lowerBound) / range.lowerBound) / log(range.upperBound / range.lowerBound)
        } else {
            fraction = (width - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
        }
        return min(max(fraction, 0), 1)
    }

    static func width(forLevel level: Int, in range: ClosedRange<CGFloat>) -> CGFloat {
        width(atPosition: position(forLevel: level), in: range)
    }

    static func level(forWidth width: CGFloat, in range: ClosedRange<CGFloat>) -> Int {
        level(atPosition: position(forWidth: width, in: range))
    }
}
