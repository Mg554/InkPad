import SwiftUI

/// Floating toolbar combining Notability's two-row layout (tools above,
/// colors and widths below) with Apple Notes-style pens that rise when picked
/// and show their color. Collapses to a small pill.
struct DrawingToolbar<InsertMenu: View>: View {
    @EnvironmentObject private var palette: ToolPalette
    @ObservedObject var canvas: CanvasController
    @Binding var pencilOnly: Bool
    @ViewBuilder let insertMenu: () -> InsertMenu

    @AppStorage("toolbarCollapsed") private var isCollapsed = false
    @State private var customColor = Color.black
    @State private var isAdjustingWidth = false

    private static var textColors: [InkColor] {
        [.init(0, 0, 0), .init(0.15, 0.40, 0.95), .init(0.90, 0.20, 0.20),
         .init(0.15, 0.65, 0.30), .init(0.95, 0.60, 0.10), .init(0.55, 0.30, 0.85)]
    }

    var body: some View {
        Group {
            if isCollapsed {
                collapsedBar
            } else {
                fullBar
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .animation(.snappy(duration: 0.2), value: isCollapsed)
        .animation(.snappy(duration: 0.15), value: palette.tool)
    }

    // MARK: Layout

    private var fullBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(DrawingTool.allCases) { tool in
                    toolButton(tool)
                }
                barDivider
                Menu {
                    insertMenu()
                } label: {
                    icon("plus.circle")
                }
                .accessibilityLabel("Insert")
                toggleButton("Ruler", systemImage: "ruler", isOn: $canvas.isRulerActive)
                toggleButton(
                    "Draw with Finger",
                    systemImage: pencilOnly ? "hand.raised.slash" : "hand.draw",
                    isOn: Binding(get: { !pencilOnly }, set: { pencilOnly = !$0 })
                )
                barDivider
                Button {
                    isCollapsed = true
                } label: {
                    icon("chevron.up")
                }
                .accessibilityLabel("Collapse Toolbar")
            }
            Divider()
            optionsRow
                .frame(minHeight: 36)
        }
    }

    private var collapsedBar: some View {
        HStack(spacing: 8) {
            Image(systemName: palette.tool.systemImage)
                .font(.title3)
            if palette.tool.isInking {
                Circle()
                    .fill(palette.style(for: palette.tool).selectedColor.color)
                    .frame(width: 18, height: 18)
            }
            Button {
                isCollapsed = false
            } label: {
                icon("chevron.down")
            }
            .accessibilityLabel("Expand Toolbar")
        }
    }

    @ViewBuilder
    private var optionsRow: some View {
        let style = palette.style(for: palette.tool)
        switch palette.tool {
        case .fountainPen, .pen, .pencil, .highlighter:
            HStack(spacing: 8) {
                ForEach(style.colors, id: \.self) { color in
                    colorSwatch(color, isSelected: color == style.selectedColor) {
                        palette.selectColor(color)
                        canvas.applyTool()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            palette.removeColor(color)
                            canvas.applyTool()
                        } label: {
                            Label("Remove Color", systemImage: "trash")
                        }
                    }
                }
                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: customColor) {
                        palette.selectCustomColor(InkColor(customColor))
                        canvas.applyTool()
                    }
                barDivider
                widthButtons(style)
            }

        case .eraser:
            HStack(spacing: 12) {
                Picker("Eraser", selection: $palette.erasesWholeStrokes) {
                    Text("Pixel").tag(false)
                    Text("Whole Stroke").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .onChange(of: palette.erasesWholeStrokes) { canvas.applyTool() }
                barDivider
                widthButtons(style)
            }

        case .lasso:
            hint("Circle ink to select it, then drag to move. Tap the selection for copy, delete and more.")

        case .text:
            switch canvas.selection {
            case .text:
                textFormattingRow
            case .image:
                HStack(spacing: 12) {
                    hint("Drag to move. Use the corner handle to resize.")
                    deleteButton
                }
            case nil:
                hint("Tap the page to add a text box. Tap a box or image to edit it.")
            }
        }
    }

    private var textFormattingRow: some View {
        let textView = canvas.selectedTextView
        _ = canvas.formattingRevision
        return HStack(spacing: 4) {
            formatButton("textformat.size.smaller", label: "Smaller") { canvas.formatText { $0.adjustFontSize(by: -2) } }
            formatButton("textformat.size.larger", label: "Larger") { canvas.formatText { $0.adjustFontSize(by: 2) } }
            barDivider
            formatButton("bold", label: "Bold", isOn: textView?.hasFontTrait(.traitBold) ?? false) {
                canvas.formatText { $0.toggleFontTrait(.traitBold) }
            }
            formatButton("italic", label: "Italic", isOn: textView?.hasFontTrait(.traitItalic) ?? false) {
                canvas.formatText { $0.toggleFontTrait(.traitItalic) }
            }
            formatButton("underline", label: "Underline", isOn: textView?.hasAttribute(.underlineStyle) ?? false) {
                canvas.formatText { $0.toggleLineStyle(.underlineStyle) }
            }
            formatButton("strikethrough", label: "Strikethrough", isOn: textView?.hasAttribute(.strikethroughStyle) ?? false) {
                canvas.formatText { $0.toggleLineStyle(.strikethroughStyle) }
            }
            formatButton("list.bullet", label: "Bulleted List") { canvas.formatText { $0.toggleBulletList() } }
            barDivider
            ForEach(Self.textColors, id: \.self) { color in
                colorSwatch(color, isSelected: false, size: 22) {
                    canvas.formatText { $0.applyTextColor(color.uiColor) }
                }
            }
            barDivider
            deleteButton
        }
    }

    // MARK: Controls

    private func toolButton(_ tool: DrawingTool) -> some View {
        let isSelected = palette.tool == tool
        let tipColor = tool.isInking ? palette.style(for: tool).selectedColor.color : Color.clear
        return Button {
            if isSelected, tool.usesWidth {
                isAdjustingWidth = true
            }
            palette.select(tool)
            canvas.applyTool()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tool.systemImage)
                    .font(.title3)
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Capsule()
                    .fill(tipColor)
                    .frame(width: 18, height: 4)
            }
            .frame(width: 40, height: 40)
            // The picked pen rises, like Apple Notes.
            .offset(y: isSelected ? -3 : 0)
        }
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func widthButtons(_ style: ToolStyle) -> some View {
        let widths = style.widths(for: palette.tool)
        return HStack(spacing: 6) {
            ForEach(widths.indices, id: \.self) { index in
                Button {
                    if index == style.widthIndex {
                        isAdjustingWidth = true
                    } else {
                        palette.selectWidth(index)
                        canvas.applyTool()
                    }
                } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: CGFloat(5 + index * 5), height: CGFloat(5 + index * 5))
                        .frame(width: 30, height: 30)
                        .background(index == style.widthIndex ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        .overlay(Circle().stroke(index == style.widthIndex ? Color.accentColor : Color.clear, lineWidth: 1.5))
                }
                .accessibilityLabel(["Thin", "Medium", "Thick"][min(index, 2)])
            }
        }
        .popover(isPresented: $isAdjustingWidth) {
            widthSlider
                .presentationCompactAdaptation(.popover)
        }
    }

    private var widthSlider: some View {
        let range = palette.tool.widthRange
        let width = Binding<Double>(
            get: { Double(palette.style(for: palette.tool).selectedWidth(for: palette.tool)) },
            set: {
                palette.setSelectedWidth(CGFloat($0))
                canvas.applyTool()
            }
        )
        return HStack(spacing: 12) {
            Slider(value: width, in: Double(range.lowerBound)...Double(range.upperBound), step: 0.5)
            Text(width.wrappedValue, format: .number.precision(.fractionLength(1)))
                .font(.callout.monospacedDigit())
                .frame(width: 44)
        }
        .padding()
        .frame(width: 320)
    }

    private func colorSwatch(_ color: InkColor, isSelected: Bool, size: CGFloat = 26, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .padding(3)
                .overlay(Circle().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5))
        }
        .accessibilityLabel("Color")
    }

    private func formatButton(_ systemImage: String, label: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 34, height: 32)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            canvas.deleteSelectedElement()
        } label: {
            Image(systemName: "trash")
                .frame(width: 34, height: 32)
        }
        .accessibilityLabel("Delete")
    }

    private func toggleButton(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            icon(systemImage)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.primary)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel(title)
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title3)
            .frame(width: 38, height: 38)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: 520)
    }

    private var barDivider: some View {
        Divider().frame(height: 26).padding(.horizontal, 2)
    }
}
