import SwiftUI

/// Customize one mind map: start from a ready style, then change any part.
struct MindMapStyleView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var style: MindMapStyle

    var body: some View {
        NavigationStack {
            Form {
                Section("Ready Styles") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(MindMapStyle.presets, id: \.name) { preset in
                                Button {
                                    withAnimation(.snappy) { style = preset.style }
                                } label: {
                                    VStack(spacing: 6) {
                                        MindStylePreview(style: preset.style)
                                            .frame(width: 110, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style == preset.style ? Color.inkAccent : Color.secondary.opacity(0.3), lineWidth: style == preset.style ? 3 : 1))
                                        Label(tr(preset.name), systemImage: preset.systemImage)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color(uiColor: .label))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    Picker(selection: $style.layout) {
                        ForEach(MindMapStyle.Layout.allCases) { layout in
                            Label(tr(layout.title), systemImage: layout.systemImage).tag(layout)
                        }
                    } label: {
                        Label("Layout", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    }
                    Picker(selection: $style.branch) {
                        ForEach(MindMapStyle.Branch.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Branches", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    LabeledSlider(title: "Spacing", systemImage: "arrow.left.and.right", value: $style.spacing, range: 0.7...1.6,
                                  text: "\(Int(style.spacing * 100))%")
                } header: {
                    Text("Shape of the Map")
                } footer: {
                    Text("Real Tree grows up from a trunk; try it with Wooden Branches and Leaf ideas. Changing the layout rearranges the map; Free keeps ideas where you put them.")
                }

                Section("Ideas") {
                    shapePicker("Central Idea", selection: $style.rootShape)
                    shapePicker("Other Ideas", selection: $style.shape)
                    Picker(selection: $style.palette) {
                        ForEach(MindMapStyle.Palette.allCases) { palette in
                            HStack {
                                Text(tr(palette.title))
                                Spacer()
                                ForEach(Array(palette.colors.prefix(5).enumerated()), id: \.offset) { item in
                                    Circle().fill(item.element).frame(width: 10, height: 10)
                                }
                            }
                            .tag(palette)
                        }
                    } label: {
                        Label("Colors", systemImage: "paintpalette")
                    }
                    Picker(selection: $style.font) {
                        ForEach(ThemeRecipe.FontStyle.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Font", systemImage: "textformat")
                    }
                    Toggle(isOn: $style.glow) {
                        Label("Glow", systemImage: "sparkles")
                    }
                }

                Section("Background") {
                    BackdropPicker(backdrop: $style.backdrop)
                }
            }
            .navigationTitle("Customize Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func shapePicker(_ title: String, selection: Binding<MindMapStyle.NodeShape>) -> some View {
        Picker(selection: selection) {
            ForEach(MindMapStyle.NodeShape.allCases) { shape in
                Label(tr(shape.title), systemImage: shape.systemImage).tag(shape)
            }
        } label: {
            Label(tr(title), systemImage: selection.wrappedValue.systemImage)
        }
    }
}

/// A tiny drawing of a style for its button.
struct MindStylePreview: View {
    let style: MindMapStyle

    var body: some View {
        ZStack {
            ScreenBackdropView(backdrop: style.backdrop, animated: false)
            Canvas { context, size in
                let colors = style.palette.colors
                let root: CGPoint
                let ends: [CGPoint]
                switch style.layout {
                case .tree:
                    root = CGPoint(x: size.width / 2, y: size.height * 0.62)
                    ends = [CGPoint(x: size.width * 0.2, y: size.height * 0.3), CGPoint(x: size.width * 0.5, y: size.height * 0.12), CGPoint(x: size.width * 0.8, y: size.height * 0.3)]
                    MindBranchPainter.drawTrunk(in: &context, at: root, scale: 0.18, wood: style.branch == .wood, color: colors[0])
                case .orgChart:
                    root = CGPoint(x: size.width / 2, y: size.height * 0.25)
                    ends = [CGPoint(x: size.width * 0.2, y: size.height * 0.75), CGPoint(x: size.width * 0.5, y: size.height * 0.75), CGPoint(x: size.width * 0.8, y: size.height * 0.75)]
                case .right:
                    root = CGPoint(x: size.width * 0.22, y: size.height / 2)
                    ends = [CGPoint(x: size.width * 0.8, y: size.height * 0.2), CGPoint(x: size.width * 0.8, y: size.height * 0.5), CGPoint(x: size.width * 0.8, y: size.height * 0.8)]
                default:
                    root = CGPoint(x: size.width / 2, y: size.height / 2)
                    ends = [CGPoint(x: size.width * 0.15, y: size.height * 0.25), CGPoint(x: size.width * 0.85, y: size.height * 0.3), CGPoint(x: size.width * 0.2, y: size.height * 0.8), CGPoint(x: size.width * 0.8, y: size.height * 0.78)]
                }
                for (index, end) in ends.enumerated() {
                    MindBranchPainter.draw(in: &context, from: root, to: end, style: style, color: colors[index % colors.count], scale: 0.35, weight: 0.6, glows: false)
                    let r: CGFloat = 5
                    context.fill(Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)), with: .color(colors[index % colors.count]))
                }
                context.fill(Path(ellipseIn: CGRect(x: root.x - 8, y: root.y - 8, width: 16, height: 16)), with: .color(colors[0]))
            }
        }
    }
}
