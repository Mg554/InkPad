import SwiftUI

/// A saved pen: tool, color, width and pressure, picked with one tap from
/// the toolbar.
struct PenPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var tool: DrawingTool
    var color: InkColor
    var width: CGFloat
    var pressureOff: Bool

    init(tool: DrawingTool, color: InkColor, width: CGFloat, pressureOff: Bool) {
        id = UUID()
        self.tool = tool
        self.color = color
        self.width = width
        self.pressureOff = pressureOff
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tool = container.value(.tool, or: DrawingTool.pen)
        color = container.value(.color, or: InkColor(0.1, 0.1, 0.12))
        width = container.value(.width, or: CGFloat(3))
        pressureOff = container.value(.pressureOff, or: false)
    }
}

/// A named set of colors, applied to the current pen's color row.
struct ColorPalette: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var colors: [InkColor]

    init(name: String, colors: [InkColor]) {
        id = UUID()
        self.name = name
        self.colors = colors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = container.value(.name, or: "Palette")
        colors = container.value(.colors, or: [InkColor]())
    }

    /// Built-in names are translated; the owner's own stay as written.
    var displayName: String {
        ColorPalette.builtIn.contains(where: { $0.id == id }) ? tr(name) : name
    }

    /// Palettes that come with the app.
    static let builtIn: [ColorPalette] = [
        ColorPalette(name: "Classic", colors: [
            InkColor(0.10, 0.10, 0.12), InkColor(0.15, 0.40, 0.95), InkColor(0.90, 0.20, 0.20),
            InkColor(0.15, 0.65, 0.30), InkColor(0.95, 0.60, 0.10), InkColor(0.55, 0.30, 0.85),
        ]),
        ColorPalette(name: "Study", colors: [
            InkColor(0.10, 0.10, 0.12), InkColor(0.80, 0.12, 0.18), InkColor(0.10, 0.35, 0.80),
            InkColor(0.05, 0.55, 0.45), InkColor(0.60, 0.25, 0.70),
        ]),
        ColorPalette(name: "Pastel", colors: [
            InkColor(0.98, 0.70, 0.75), InkColor(0.70, 0.85, 0.98), InkColor(0.72, 0.92, 0.75),
            InkColor(0.99, 0.88, 0.62), InkColor(0.82, 0.74, 0.96), InkColor(0.98, 0.78, 0.62),
        ]),
        ColorPalette(name: "Earth", colors: [
            InkColor(0.36, 0.25, 0.18), InkColor(0.55, 0.42, 0.25), InkColor(0.42, 0.50, 0.30),
            InkColor(0.70, 0.45, 0.30), InkColor(0.25, 0.35, 0.40),
        ]),
        ColorPalette(name: "Neon", colors: [
            InkColor(1.00, 0.20, 0.55), InkColor(0.10, 0.90, 0.95), InkColor(0.60, 1.00, 0.20),
            InkColor(1.00, 0.85, 0.10), InkColor(0.70, 0.35, 1.00),
        ]),
    ]
}

extension ToolPalette {
    /// Saves the current pen, color and width as a preset.
    func saveCurrentAsPreset() {
        guard tool.isInking else { return }
        let style = style(for: tool)
        let preset = PenPreset(
            tool: tool,
            color: style.selectedColor,
            width: style.selectedWidth(for: tool),
            pressureOff: style.ignoresPressure(for: tool)
        )
        guard !presets.contains(where: { $0.tool == preset.tool && $0.color == preset.color && $0.width == preset.width }) else { return }
        presets.append(preset)
    }

    /// Picks the preset's pen with its color and width.
    func apply(_ preset: PenPreset) {
        select(preset.tool)
        selectColor(preset.color)
        let widths = style(for: preset.tool).widths(for: preset.tool)
        if let index = widths.firstIndex(of: preset.width) {
            selectWidth(index)
        } else {
            // The nearest width preset takes the saved width.
            var nearest = 0
            for (index, width) in widths.enumerated() where abs(width - preset.width) < abs(widths[nearest] - preset.width) {
                nearest = index
            }
            selectWidth(nearest)
            setSelectedWidth(preset.width)
        }
        setIgnoresPressure(preset.pressureOff)
    }

    /// The preset matching what is selected now, if any.
    var activePresetID: UUID? {
        let style = style(for: tool)
        let width = style.selectedWidth(for: tool)
        return presets.first(where: { $0.tool == tool && $0.color == style.selectedColor && $0.width == width })?.id
    }

    func removePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
    }

    /// Every palette: the owner's first, then the built-in ones.
    var allPalettes: [ColorPalette] { palettes + ColorPalette.builtIn }

    /// Puts the palette's colors in the current pen's color row.
    func applyPalette(_ palette: ColorPalette) {
        guard !palette.colors.isEmpty else { return }
        setColors(palette.colors)
    }

    /// Saves the current pen's colors as a named palette.
    func saveColorsAsPalette(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let colors = style(for: tool).colors
        guard !colors.isEmpty else { return }
        palettes.append(ColorPalette(name: trimmed.isEmpty ? tr("My Palette") : trimmed, colors: colors))
    }

    func removePalette(_ id: UUID) {
        palettes.removeAll { $0.id == id }
    }

    func renamePalette(_ id: UUID, to name: String) {
        guard let index = palettes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { palettes[index].name = trimmed }
    }
}

/// One preset in the toolbar: the pen in its color, with a dot for its width.
struct PenPresetChip: View {
    let preset: PenPreset
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: preset.tool.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(preset.color.color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(isSelected ? Color.inkAccent.opacity(0.18) : Color.primary.opacity(0.05)))
                .overlay(Circle().stroke(isSelected ? Color.inkAccent : Color.clear, lineWidth: 1.5))
            Circle()
                .fill(preset.color.color)
                .frame(width: dotSize, height: dotSize)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
        .frame(width: 34, height: 34)
    }

    private var dotSize: CGFloat {
        let range = preset.tool.widthRange
        let span: CGFloat = max(range.upperBound - range.lowerBound, 1)
        let share: CGFloat = (preset.width - range.lowerBound) / span
        return 5 + 7 * min(max(share, 0), 1)
    }
}

/// Lists, reorders and deletes pen presets and palettes.
struct PenPresetsEditor: View {
    @EnvironmentObject private var palette: ToolPalette

    var body: some View {
        List {
            Section {
                if palette.presets.isEmpty {
                    Text("Pick a pen, color and width, then tap + beside the pens in the toolbar.")
                        .foregroundStyle(.secondary)
                }
                ForEach(palette.presets) { preset in
                    HStack(spacing: 12) {
                        PenPresetChip(preset: preset, isSelected: false)
                        Text(tr(preset.tool.title))
                        Spacer()
                        Text(verbatim: String(format: "%.1f pt", Double(preset.width)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { palette.removePreset(palette.presets[index].id) }
                }
                .onMove { palette.movePresets(from: $0, to: $1) }
            } header: {
                Text("Pen Presets")
            }
            Section {
                ForEach(palette.palettes) { item in
                    paletteRow(item)
                }
                .onDelete { offsets in
                    for index in offsets { palette.removePalette(palette.palettes[index].id) }
                }
                ForEach(ColorPalette.builtIn) { item in
                    paletteRow(item)
                }
            } header: {
                Text("Color Palettes")
            } footer: {
                Text("Save a pen's colors as a palette from the palette button next to its colors.")
            }
        }
        .navigationTitle("Pens & Palettes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paletteRow(_ item: ColorPalette) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: item.displayName)
            Spacer()
            HStack(spacing: 3) {
                ForEach(Array(item.colors.prefix(8).enumerated()), id: \.offset) { _, color in
                    Circle().fill(color.color).frame(width: 14, height: 14)
                }
            }
        }
    }
}
