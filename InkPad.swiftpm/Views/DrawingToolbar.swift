import SwiftUI

/// Floating Notability-style toolbar: tools on top, colors and widths below.
struct DrawingToolbar: View {
    @EnvironmentObject private var palette: ToolPalette
    @ObservedObject var canvas: CanvasController
    @Binding var pencilOnly: Bool
    @State private var customColor = Color.black

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(DrawingTool.allCases) { tool in
                    toolButton(tool)
                }
                Divider().frame(height: 28)
                toggleButton("Ruler", systemImage: "ruler", isOn: $canvas.isRulerActive)
                toggleButton(
                    pencilOnly ? "Pencil Only" : "Finger Drawing",
                    systemImage: pencilOnly ? "applepencil" : "hand.draw",
                    isOn: Binding(get: { !pencilOnly }, set: { pencilOnly = !$0 })
                )
            }

            let style = palette.style(for: palette.tool)
            if palette.tool.usesColor || palette.tool.usesWidth {
                HStack(spacing: 10) {
                    if palette.tool.usesColor {
                        ForEach(style.colors, id: \.self) { color in
                            colorSwatch(color, isSelected: color == style.selectedColor)
                        }
                        ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                            .labelsHidden()
                            .onChange(of: customColor) {
                                palette.selectCustomColor(InkColor(customColor))
                                canvas.applyTool()
                            }
                        Divider().frame(height: 24)
                    }
                    if palette.tool == .eraser {
                        Toggle("Whole Strokes", isOn: $palette.erasesWholeStrokes)
                            .toggleStyle(.button)
                            .font(.footnote)
                            .onChange(of: palette.erasesWholeStrokes) { canvas.applyTool() }
                    }
                    ForEach(Array(palette.tool.widthPresets.enumerated()), id: \.offset) { index, _ in
                        widthButton(index, isSelected: index == style.widthIndex)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        Button {
            palette.select(tool)
            canvas.applyTool()
        } label: {
            Image(systemName: tool.systemImage)
                .font(.title3)
                .frame(width: 40, height: 36)
                .foregroundStyle(palette.tool == tool ? Color.white : Color.primary)
                .background(palette.tool == tool ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel(tool.title)
    }

    private func toggleButton(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 40, height: 36)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.primary)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel(title)
    }

    private func colorSwatch(_ color: InkColor, isSelected: Bool) -> some View {
        Button {
            palette.selectColor(color)
            canvas.applyTool()
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .padding(3)
                .overlay(Circle().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5))
        }
        .contextMenu {
            Button(role: .destructive) {
                palette.removeColor(color)
                canvas.applyTool()
            } label: {
                Label("Remove Color", systemImage: "trash")
            }
        }
        .accessibilityLabel("Color")
    }

    private func widthButton(_ index: Int, isSelected: Bool) -> some View {
        Button {
            palette.selectWidth(index)
            canvas.applyTool()
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: CGFloat(6 + index * 6), height: CGFloat(6 + index * 6))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
        }
        .accessibilityLabel(["Thin", "Medium", "Thick"][min(index, 2)])
    }
}
