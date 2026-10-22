import SwiftUI

/// Notability-style "Style" panel for lasso-selected ink: stroke size,
/// stroke style (solid, dashed, dotted) and color, all applied live.
struct SelectionStylePanel: View {
    @ObservedObject var selection: SelectionStyleModel
    @State private var customColor = Color.black
    @State private var pickedColor: InkColor?

    private static let colors: [InkColor] = [
        .init(0.85, 0.87, 0.92), .init(0.90, 0.20, 0.20), .init(0.98, 0.92, 0.25), .init(0.95, 0.85, 0.30),
        .init(0.80, 0.60, 0.20), .init(0.10, 0.10, 0.12), .init(0.25, 0.25, 0.28), .init(0.45, 0.45, 0.48),
        .init(0.60, 0.50, 0.95), .init(0.35, 0.65, 0.20), .init(0.30, 0.70, 0.30), .init(0.55, 0.90, 0.30),
        .init(0.20, 0.50, 0.90), .init(0.30, 0.60, 0.95), .init(0.95, 0.30, 0.30), .init(0.85, 0.15, 0.20),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Stroke")
                .font(.headline)
            WidthLevelBar(level: $selection.level)

            HStack(spacing: 10) {
                ForEach(LassoSelection.DashStyle.allCases) { style in
                    Button {
                        selection.dash = style
                    } label: {
                        StrokeStyleSample(style: style)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.secondary.opacity(selection.dash == style ? 0.15 : 0.07), in: Capsule())
                            .overlay(Capsule().stroke(selection.dash == style ? Color.accentColor : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(style.rawValue.capitalized)
                }
            }

            HStack {
                Text("Colors")
                    .font(.headline)
                Spacer()
                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: customColor) {
                        pickedColor = nil
                        selection.setColor(customColor)
                    }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 12) {
                ForEach(Self.colors, id: \.self) { color in
                    Button {
                        pickedColor = color
                        selection.setColor(color.color)
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Color.primary.opacity(0.12)))
                            .overlay {
                                if pickedColor == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .shadow(radius: 1)
                                }
                            }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// A small wavy line drawn solid, dashed or dotted.
private struct StrokeStyleSample: View {
    let style: LassoSelection.DashStyle

    var body: some View {
        Canvas { context, size in
            var wave = Path()
            wave.move(to: CGPoint(x: 12, y: size.height / 2))
            wave.addCurve(
                to: CGPoint(x: size.width - 12, y: size.height / 2),
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.1),
                control2: CGPoint(x: size.width * 0.65, y: size.height * 0.9)
            )
            var dash: [CGFloat] = []
            if style == .dashed { dash = [8, 6] }
            if style == .dotted { dash = [0.1, 6] }
            context.stroke(wave, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dash))
        }
        .frame(height: 30)
    }
}
