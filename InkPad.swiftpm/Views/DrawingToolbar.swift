import SwiftUI

/// Floating toolbar combining Notability's two-row layout (tools above,
/// colors and widths below) with Apple Notes-style pens that rise when picked
/// and show their color. Drag it by its handle or any empty part of the bar
/// to dock it on any edge: on the left or right it stands upright in two
/// columns, pens pointing at the page.
/// Collapses to a small pill, or hides completely.
struct DrawingToolbar<InsertMenu: View>: View {
    @EnvironmentObject private var palette: ToolPalette
    @ObservedObject var canvas: CanvasController
    @Binding var pencilOnly: Bool
    /// The edge the toolbar is docked to.
    let edge: ToolbarEdge
    /// Dragging the grip, measured in `ToolbarPlacement.coordinateSpace`.
    let onMove: (DragGesture.Value) -> Void
    let onMoveEnded: (DragGesture.Value) -> Void
    let onHide: () -> Void
    @ViewBuilder let insertMenu: () -> InsertMenu

    @AppStorage("toolbarCollapsed") private var isCollapsed = false
    @State private var customColor = Color.black
    @State private var isAdjustingWidth = false

    private var isVertical: Bool { edge.isVertical }

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
        .padding(.horizontal, isVertical ? 6 : 10)
        .padding(.vertical, isVertical ? 10 : 6)
        .background {
            // Dragging the bar itself (between its buttons) moves it, like Notability.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .contentShape(Rectangle())
                .gesture(moveGesture)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08)).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .animation(.snappy(duration: 0.2), value: isCollapsed)
        .animation(.snappy(duration: 0.15), value: palette.tool)
    }

    // MARK: Layout

    /// Tools and options side by side when upright (tools nearest the screen
    /// edge), otherwise in two rows.
    @ViewBuilder
    private var fullBar: some View {
        if isVertical {
            HStack(alignment: .top, spacing: 4) {
                if edge == .trailing {
                    optionsStack
                    toolsStack
                        .padding(.leading, 4)
                        .overlay(alignment: .leading) { hairline }
                } else {
                    toolsStack
                        .padding(.trailing, 4)
                        .overlay(alignment: .trailing) { hairline }
                    optionsStack
                }
            }
        } else {
            VStack(spacing: 4) {
                toolsStack
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) { hairline }
                optionsStack
            }
        }
    }

    /// Scrolls when the screen is too small for every tool; the handle stays
    /// outside the scrolling part so dragging it always moves the bar.
    private var toolsStack: some View {
        AxisStack(vertical: isVertical, spacing: isVertical ? 0 : 2) {
            grip
            scrollingIfNeeded(isVertical ? .vertical : .horizontal) {
                AxisStack(vertical: isVertical, spacing: isVertical ? 0 : 2) {
                    ForEach(DrawingTool.allCases) { tool in
                        toolButton(tool)
                    }
                    barDivider
                    actionButtons
                }
            }
        }
    }

    private var optionsStack: some View {
        AxisStack(vertical: isVertical, spacing: isVertical ? 6 : 8) {
            optionsContent
        }
        .frame(minWidth: isVertical ? 38 : nil, minHeight: isVertical ? nil : 36)
    }

    private var collapsedBar: some View {
        AxisStack(vertical: isVertical, spacing: 8) {
            grip
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
                icon(expandSymbol)
            }
            .accessibilityLabel("Expand Toolbar")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Menu {
            insertMenu()
        } label: {
            icon("plus.circle")
        }
        .accessibilityLabel("Insert")
        toggleButton("Ruler", systemImage: "ruler", isOn: $canvas.isRulerActive)
        toggleButton("Hold to Snap Shapes", systemImage: "skew", isOn: $palette.snapsShapes)
        toggleButton(
            "Draw with Finger",
            systemImage: pencilOnly ? "hand.raised.slash" : "hand.draw",
            isOn: Binding(get: { !pencilOnly }, set: { pencilOnly = !$0 })
        )
        barDivider
        Button(action: onHide) {
            icon("eye.slash")
        }
        .accessibilityLabel("Hide Toolbar")
        Button {
            isCollapsed = true
        } label: {
            icon(collapseSymbol)
        }
        .accessibilityLabel("Collapse Toolbar")
    }

    /// Colors and widths for pens, eraser modes, or text formatting, laid out
    /// along the bar.
    @ViewBuilder
    private var optionsContent: some View {
        let style = palette.style(for: palette.tool)
        switch palette.tool {
        case .quill, .fountainPen, .pen, .monoline, .pencil, .crayon, .watercolor, .marker, .highlighter:
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

        case .eraser:
            eraserModes
            eraserReturnToggle
            barDivider
            widthButtons(style)

        case .lasso:
            hint("Circle ink to select it, then drag to move. Tap the selection for Style, Duplicate, Cut, Copy and Paste.")

        case .text:
            switch canvas.selection {
            case .text:
                textFormattingItems
            case .image:
                hint("Drag to move. Use the corner handle to resize.")
                deleteButton
            case nil:
                textInputModeButton
                hint("Tap the page to add a text box. Tap a box or image to edit it.")
            }
        }
    }

    private var textFormattingItems: some View {
        let textView = canvas.selectedTextView
        _ = canvas.formattingRevision
        return Group {
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
            textInputModeButton
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

    // MARK: Eraser

    @ViewBuilder
    private var eraserModes: some View {
        if isVertical {
            toggleButton("Pixel Eraser", systemImage: "eraser", isOn: eraserMode(wholeStrokes: false))
            toggleButton("Whole Stroke Eraser", systemImage: "eraser.line.dashed", isOn: eraserMode(wholeStrokes: true))
        } else {
            Picker("Eraser", selection: $palette.erasesWholeStrokes) {
                Text("Pixel").tag(false)
                Text("Whole Stroke").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .onChange(of: palette.erasesWholeStrokes) { canvas.applyTool() }
        }
    }

    private func eraserMode(wholeStrokes: Bool) -> Binding<Bool> {
        Binding(
            get: { palette.erasesWholeStrokes == wholeStrokes },
            set: { isOn in
                guard isOn else { return }
                palette.erasesWholeStrokes = wholeStrokes
                canvas.applyTool()
            }
        )
    }

    /// After erasing, go straight back to the tool used before the eraser.
    private var eraserReturnToggle: some View {
        let isOn = palette.returnsAfterErasing
        return Button {
            palette.returnsAfterErasing.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                if !isVertical {
                    Text("Back to Last Tool")
                        .font(.footnote.weight(.medium))
                }
            }
            .padding(.horizontal, isVertical ? 0 : 10)
            .frame(minWidth: 38, minHeight: 32)
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
        }
        .accessibilityLabel("Switch Back to the Last Tool After Erasing")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Tools

    private func toolButton(_ tool: DrawingTool) -> some View {
        let isSelected = palette.tool == tool
        return Button {
            if isSelected, tool.usesWidth {
                isAdjustingWidth = true
            }
            palette.select(tool)
            canvas.applyTool()
        } label: {
            ZStack(alignment: markAlignment) {
                toolImage(tool, isSelected: isSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tool.isInking ? tipAlignment : .center)
                    .offset(tool.isInking ? penSink(isSelected: isSelected) : .zero)
                // Notability's mark under (or beside) the selected tool.
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: isVertical ? 3 : 18, height: isVertical ? 18 : 3)
            }
            .frame(width: isVertical ? 44 : 34, height: isVertical ? 32 : 44)
            .clipped()
        }
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func toolImage(_ tool: DrawingTool, isSelected: Bool) -> some View {
        if tool.isInking {
            // Realistic pens, like Apple Notes, pointing at the page.
            PenIcon(tool: tool, color: palette.style(for: tool).selectedColor.color)
                .frame(width: 22, height: 38)
                .rotationEffect(.degrees(penAngle))
                .frame(width: isVertical ? 38 : 22, height: isVertical ? 22 : 38)
        } else {
            Image(systemName: tool.systemImage)
                .font(.title3)
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
    }

    /// Pens point up in a horizontal bar and sideways toward the page when upright.
    private var penAngle: Double {
        switch edge {
        case .leading: 90
        case .trailing: -90
        case .top, .bottom: 0
        }
    }

    private var tipAlignment: Alignment {
        switch edge {
        case .leading: .trailing
        case .trailing: .leading
        case .top, .bottom: .top
        }
    }

    private var markAlignment: Alignment {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        case .top, .bottom: .bottom
        }
    }

    /// Pens sit low in their slot and rise toward the page when picked.
    private func penSink(isSelected: Bool) -> CGSize {
        let depth: CGFloat = isSelected ? 2 : 8
        switch edge {
        case .leading: return CGSize(width: -depth, height: 0)
        case .trailing: return CGSize(width: depth, height: 0)
        case .top, .bottom: return CGSize(width: 0, height: depth)
        }
    }

    // MARK: Widths

    private func widthButtons(_ style: ToolStyle) -> some View {
        let widths = style.widths(for: palette.tool)
        return AxisStack(vertical: isVertical, spacing: 6) {
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

    /// Notability-style width bar with a live preview stroke; drag along it to
    /// change the width smoothly.
    private var widthSlider: some View {
        let tool = palette.tool
        let style = palette.style(for: tool)
        let range = tool.widthRange
        let current = style.selectedWidth(for: tool)
        let previewColor = tool.isInking ? style.selectedColor.color : Color.secondary

        return VStack(spacing: 14) {
            // Preview of the stroke at the chosen width.
            Canvas { context, size in
                var wave = Path()
                wave.move(to: CGPoint(x: 12, y: size.height / 2))
                wave.addCurve(
                    to: CGPoint(x: size.width - 12, y: size.height / 2),
                    control1: CGPoint(x: size.width * 0.35, y: -size.height * 0.2),
                    control2: CGPoint(x: size.width * 0.65, y: size.height * 1.2)
                )
                let opacity = tool == .highlighter ? DrawingTool.highlighterOpacity : 1
                let lineWidth = min(current, size.height - 4)
                if style.ignoresPressure(for: tool) || !tool.isInking {
                    context.stroke(
                        wave,
                        with: .color(previewColor.opacity(opacity)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                } else {
                    // With pressure on, the stroke swells in the middle.
                    for (fraction, factor) in [(0.0, 0.5), (0.2, 0.8), (0.4, 1.0), (0.6, 1.0), (0.8, 0.8)] {
                        context.stroke(
                            wave.trimmedPath(from: fraction, to: fraction + 0.2),
                            with: .color(previewColor.opacity(opacity)),
                            style: StrokeStyle(lineWidth: lineWidth * factor, lineCap: .round)
                        )
                    }
                }
            }
            .frame(height: 44)

            // Levels 1...20, mapped onto the tool's real width range.
            WidthLevelBar(level: Binding(
                get: { WidthLevelBar.level(forWidth: current, in: range) },
                set: {
                    palette.setSelectedWidth(WidthLevelBar.width(forLevel: $0, in: range))
                    canvas.applyTool()
                }
            ))
            if tool.isInking {
                Divider()
                Toggle(isOn: Binding(
                    get: { !palette.style(for: tool).ignoresPressure(for: tool) },
                    set: { palette.setIgnoresPressure(!$0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pressure Sensitivity")
                        Text("Off keeps the width even however hard you press.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 340)
    }

    // MARK: Controls

    /// The handle for dragging the toolbar to another edge.
    private var grip: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: isVertical ? 26 : 5, height: isVertical ? 5 : 26)
            .frame(width: isVertical ? 44 : 24, height: isVertical ? 24 : 44)
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .accessibilityLabel("Move Toolbar")
            .accessibilityHint("Drag to any edge of the screen.")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ToolbarPlacement.coordinateSpace))
            .onChanged { onMove($0) }
            .onEnded { onMoveEnded($0) }
    }

    /// Chevrons point toward the edge to collapse and away from it to expand.
    private var collapseSymbol: String {
        switch edge {
        case .top: "chevron.up"
        case .bottom: "chevron.down"
        case .leading: "chevron.left"
        case .trailing: "chevron.right"
        }
    }

    private var expandSymbol: String {
        switch edge {
        case .top: "chevron.down"
        case .bottom: "chevron.up"
        case .leading: "chevron.right"
        case .trailing: "chevron.left"
        }
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

    /// Typing on the keyboard, or handwriting turned into text.
    private var textInputModeButton: some View {
        _ = canvas.formattingRevision
        let mode = TextInputMode.current
        return Button {
            canvas.toggleTextInputMode()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.switchSymbol)
                if !isVertical {
                    Text(mode == .keyboard ? "Write with Pencil" : "Use Keyboard")
                        .font(.footnote.weight(.medium))
                }
            }
            .padding(.horizontal, isVertical ? 0 : 10)
            .frame(minWidth: 38, minHeight: 32)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel(mode.switchLabel)
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
            .frame(width: 38, height: isVertical ? 34 : 38)
    }

    /// A line of tips in a horizontal bar; an info button when upright.
    @ViewBuilder
    private func hint(_ text: String) -> some View {
        if isVertical {
            HintButton(text: text)
        } else {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 520)
        }
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: isVertical ? 26 : 1, height: isVertical ? 1 : 26)
            .padding(isVertical ? .vertical : .horizontal, 4)
    }

    /// The line between the tools and the options, as long as what it overlays.
    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
    }

    /// The content as it is when it fits, otherwise scrollable along `axis`.
    private func scrollingIfNeeded<Content: View>(_ axis: Axis.Set, @ViewBuilder content: () -> Content) -> some View {
        let built = content()
        return ViewThatFits(in: axis) {
            built
            ScrollView(axis, showsIndicators: false) {
                built
            }
        }
    }
}

/// An HStack, or a VStack when `vertical`.
private struct AxisStack<Content: View>: View {
    let vertical: Bool
    var spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if vertical {
            VStack(spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }
}

/// An info button showing a tip, for the upright toolbar where a line of
/// text does not fit.
private struct HintButton: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .frame(width: 38, height: 34)
        }
        .accessibilityLabel(text)
        .popover(isPresented: $isShowing) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
    }
}
