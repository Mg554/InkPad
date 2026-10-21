import PencilKit
import SwiftUI

enum DrawingTool: String, Codable, CaseIterable, Identifiable {
    case quill, fountainPen, pen, monoline, pencil, crayon, watercolor, marker, highlighter, eraser, text, lasso

    var id: Self { self }

    var title: String {
        switch self {
        case .quill: "Quill"
        case .fountainPen: "Fountain Pen"
        case .pen: "Pen"
        case .monoline: "Monoline"
        case .pencil: "Pencil"
        case .crayon: "Crayon"
        case .watercolor: "Watercolor"
        case .marker: "Marker"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .text: "Text"
        case .lasso: "Lasso"
        }
    }

    var systemImage: String {
        switch self {
        case .quill: "signature"
        case .fountainPen: "paintbrush.pointed"
        case .pen: "pencil.tip"
        case .monoline: "pencil.line"
        case .pencil: "pencil"
        case .crayon: "pencil.and.scribble"
        case .watercolor: "paintbrush"
        case .marker: "highlighter"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .text: "textformat"
        case .lasso: "lasso"
        }
    }

    /// Pens and the highlighter: they have colors and draw ink.
    var isInking: Bool {
        switch self {
        case .eraser, .text, .lasso: false
        default: true
        }
    }

    var usesWidth: Bool { isInking || self == .eraser }

    /// The PencilKit ink behind each pen. The quill is a broad fountain-pen
    /// nib (thick downstrokes, thin sideways strokes), like an old dip pen.
    /// The highlighter is Notability-style: an even, see-through stroke that
    /// does not change with pressure (see `highlighterOpacity`); the marker is
    /// PencilKit's own felt-tip marker, as in Apple Notes.
    var inkType: PKInkingTool.InkType? {
        switch self {
        case .quill, .fountainPen: .fountainPen
        case .pen: .pen
        case .monoline, .highlighter: .monoline
        case .pencil: .pencil
        case .crayon: .crayon
        case .watercolor: .watercolor
        case .marker: .marker
        case .eraser, .text, .lasso: nil
        }
    }

    /// Highlighter ink is translucent so text underneath stays readable.
    static let highlighterOpacity: CGFloat = 0.38

    /// The range offered by the width slider.
    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .pen, .fountainPen, .monoline: 0.5...20
        case .quill: 2...30
        case .pencil, .crayon: 1...24
        case .watercolor: 2...40
        case .marker: 2...40
        case .highlighter: 4...60
        case .eraser: 4...100
        case .text, .lasso: 1...1
        }
    }

    /// Three width presets (thin, medium, thick) in canvas points.
    var widthPresets: [CGFloat] {
        switch self {
        case .pen, .fountainPen, .monoline: [1.5, 3, 6]
        case .quill: [5, 9, 15]
        case .pencil, .crayon: [2.5, 5, 10]
        case .watercolor: [6, 12, 22]
        case .marker: [4, 8, 16]
        case .highlighter: [10, 18, 30]
        case .eraser: [8, 20, 50]
        case .text, .lasso: []
        }
    }

    var defaultColors: [InkColor] {
        switch self {
        case .highlighter:
            [.init(0.98, 0.92, 0.25), .init(0.55, 0.92, 0.35), .init(0.45, 0.85, 0.98),
             .init(0.98, 0.55, 0.75), .init(0.99, 0.70, 0.30), .init(0.75, 0.60, 0.98)]
        case .quill:
            // Iron-gall browns and inks of old letters.
            [.init(0.24, 0.15, 0.09), .init(0.08, 0.08, 0.10), .init(0.12, 0.18, 0.40),
             .init(0.45, 0.10, 0.10), .init(0.35, 0.28, 0.12)]
        default:
            [.init(0.10, 0.10, 0.12), .init(0.15, 0.40, 0.95), .init(0.90, 0.20, 0.20),
             .init(0.15, 0.65, 0.30), .init(0.95, 0.60, 0.10), .init(0.55, 0.30, 0.85)]
        }
    }
}

/// An sRGB color that can be stored in user defaults.
struct InkColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(Double(red), Double(green), Double(blue))
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    var color: Color { Color(uiColor) }
}

/// Per-tool palette: preset colors, the selected color and width.
struct ToolStyle: Codable, Equatable {
    var colors: [InkColor]
    var selectedColor: InkColor
    var widthIndex: Int
    /// Widths the user set with the slider, replacing the tool's presets.
    var customWidths: [CGFloat]?

    func widths(for tool: DrawingTool) -> [CGFloat] {
        let presets = tool.widthPresets
        guard let customWidths, customWidths.count == presets.count else { return presets }
        return customWidths
    }

    func selectedWidth(for tool: DrawingTool) -> CGFloat {
        let widths = widths(for: tool)
        return widths.isEmpty ? 0 : widths[min(max(widthIndex, 0), widths.count - 1)]
    }

    init(tool: DrawingTool) {
        colors = tool.defaultColors
        selectedColor = colors.first ?? InkColor(0, 0, 0)
        widthIndex = 1
    }
}

/// The selected drawing tool and each tool's style. Shared by all notes and
/// remembered between launches.
@MainActor
final class ToolPalette: ObservableObject {
    private struct Saved: Codable {
        var tool: DrawingTool
        var styles: [DrawingTool: ToolStyle]
        var erasesWholeStrokes: Bool
        var snapsShapes: Bool?
    }

    private static let defaultsKey = "toolPalette"

    @Published var tool: DrawingTool = .pen { didSet { save() } }
    @Published private(set) var styles: [DrawingTool: ToolStyle] = [:] { didSet { save() } }
    @Published var erasesWholeStrokes = false { didSet { save() } }
    /// Hold the pencil still at the end of a stroke to turn it into a straight
    /// line or shape.
    @Published var snapsShapes = true { didSet { save() } }

    /// The tool to return to after a temporary switch (Apple Pencil double-tap).
    private var previousTool: DrawingTool = .pen

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            tool = saved.tool
            styles = saved.styles
            erasesWholeStrokes = saved.erasesWholeStrokes
            snapsShapes = saved.snapsShapes ?? true
        }
    }

    func style(for tool: DrawingTool) -> ToolStyle {
        styles[tool] ?? ToolStyle(tool: tool)
    }

    func select(_ newTool: DrawingTool) {
        if newTool != tool { previousTool = tool }
        tool = newTool
    }

    /// Switches to the eraser, or back to the previous tool when already erasing.
    func toggleEraser() {
        select(tool == .eraser ? (previousTool == .eraser ? .pen : previousTool) : .eraser)
    }

    func selectColor(_ color: InkColor) {
        var style = style(for: tool)
        style.selectedColor = color
        if !style.colors.contains(color) {
            style.colors.append(color)
        }
        styles[tool] = style
    }

    /// For the color picker, which reports every intermediate color while
    /// dragging: replaces the selected custom color instead of adding another.
    func selectCustomColor(_ color: InkColor) {
        var style = style(for: tool)
        if !tool.defaultColors.contains(style.selectedColor),
           let index = style.colors.firstIndex(of: style.selectedColor) {
            style.colors[index] = color
        } else if !style.colors.contains(color) {
            style.colors.append(color)
        }
        style.selectedColor = color
        styles[tool] = style
    }

    func removeColor(_ color: InkColor) {
        var style = style(for: tool)
        guard style.colors.count > 1 else { return }
        style.colors.removeAll { $0 == color }
        if style.selectedColor == color, let first = style.colors.first {
            style.selectedColor = first
        }
        styles[tool] = style
    }

    /// Changes the selected width preset's value (from the slider).
    func setSelectedWidth(_ width: CGFloat) {
        var style = style(for: tool)
        var widths = style.widths(for: tool)
        guard widths.indices.contains(style.widthIndex) else { return }
        let range = tool.widthRange
        widths[style.widthIndex] = min(max(width, range.lowerBound), range.upperBound)
        style.customWidths = widths
        styles[tool] = style
    }

    func selectWidth(_ index: Int) {
        var style = style(for: tool)
        style.widthIndex = index
        styles[tool] = style
    }

    /// The PencilKit tool for the current selection.
    var pkTool: PKTool {
        let style = style(for: tool)
        let width = style.selectedWidth(for: tool)
        let color = style.selectedColor.uiColor
        switch tool {
        case .eraser:
            return PKEraserTool(erasesWholeStrokes ? .vector : .bitmap, width: width)
        case .lasso, .text:
            // Drawing is switched off while the Text tool is active.
            return PKLassoTool()
        case .highlighter:
            return PKInkingTool(.monoline, color: color.withAlphaComponent(DrawingTool.highlighterOpacity), width: width)
        default:
            return PKInkingTool(tool.inkType ?? .pen, color: color, width: width)
        }
    }

    private func save() {
        let saved = Saved(tool: tool, styles: styles, erasesWholeStrokes: erasesWholeStrokes, snapsShapes: snapsShapes)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
