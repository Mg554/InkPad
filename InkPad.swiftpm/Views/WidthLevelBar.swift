import SwiftUI

/// Notability-style size bar with levels 1...20. Drag or tap along it; the
/// level follows the pencil continuously and is reported immediately.
struct WidthLevelBar: View {
    static let levels = 20

    @Binding var level: Int

    var body: some View {
        GeometryReader { geometry in
            let levels = Self.levels
            let fraction = CGFloat(level - 1) / CGFloat(levels - 1)
            let barWidth = geometry.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(1...levels, id: \.self) { step in
                        Capsule()
                            .fill(step <= level ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: 5 + CGFloat(step) * 0.6)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 30)
                Text("\(level)")
                    .font(.caption.bold().monospacedDigit())
                    .frame(width: 34, height: 34)
                    .background(.background, in: Circle())
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: .accentColor.opacity(0.5), radius: 6)
                    .offset(x: fraction * (barWidth - 34))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = min(max((value.location.x - 17) / max(barWidth - 34, 1), 0), 1)
                        let next = 1 + Int((position * CGFloat(levels - 1)).rounded())
                        if next != level { level = next }
                    }
            )
        }
        .frame(height: 40)
        .sensoryFeedback(.selection, trigger: level)
    }

    /// Maps a level onto a real width in `range`.
    static func width(forLevel level: Int, in range: ClosedRange<CGFloat>) -> CGFloat {
        let fraction = CGFloat(min(max(level, 1), levels) - 1) / CGFloat(levels - 1)
        return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }

    static func level(forWidth width: CGFloat, in range: ClosedRange<CGFloat>) -> Int {
        let span = max(range.upperBound - range.lowerBound, 0.001)
        let fraction = min(max((width - range.lowerBound) / span, 0), 1)
        return 1 + Int((fraction * CGFloat(levels - 1)).rounded())
    }
}
