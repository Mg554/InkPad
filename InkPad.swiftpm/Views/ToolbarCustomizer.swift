import SwiftUI

/// "Customize Toolbar", like Notability's Toolbox: show or hide each tool
/// and drag to put them in your order.
struct ToolbarCustomizer: View {
    @EnvironmentObject private var palette: ToolPalette
    @Environment(\.dismiss) private var dismiss
    /// Called after a change, so the canvas picks up a newly selected tool.
    let onChange: () -> Void

    /// Pages pushed from here. Buttons, not NavigationLinks: the list is
    /// always in edit mode (to reorder tools), which turns links off.
    enum Page: Hashable { case pens, gestures }
    @State private var path: [Page] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(palette.toolbarOrder) { tool in
                        row(tool)
                    }
                    .onMove { source, destination in
                        palette.moveTools(from: source, to: destination)
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("Show or hide tools, and drag the handles to reorder them. At least one tool stays in the toolbar.")
                }

                Section {
                    pageButton("Pens & Palettes", systemImage: "swatchpalette", page: .pens)
                    pageButton("Gestures", systemImage: "hand.tap", page: .gestures)
                }

                Section {
                    Button("Reset to Default", role: .destructive) {
                        palette.resetToolbar()
                        onChange()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationDestination(for: Page.self) { page in
                Group {
                    switch page {
                    case .pens: PenPresetsEditor()
                    case .gestures: GestureSettingsView()
                    }
                }
                .environment(\.editMode, .constant(.inactive))
            }
            .navigationTitle("Customize Toolbar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func pageButton(_ title: LocalizedStringKey, systemImage: String, page: Page) -> some View {
        Button {
            path.append(page)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(Color.primary)
    }

    private func row(_ tool: DrawingTool) -> some View {
        let isShown = palette.isShown(tool)
        return HStack(spacing: 14) {
            Button {
                palette.setShown(!isShown, for: tool)
                onChange()
            } label: {
                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isShown ? Color.inkAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShown ? "Hide \(tool.title)" : "Show \(tool.title)")

            Group {
                if tool.isInking {
                    PenIcon(tool: tool, color: palette.style(for: tool).selectedColor.color)
                        .frame(width: 18, height: 32)
                        .rotationEffect(.degrees(90))
                } else {
                    Image(systemName: tool.systemImage)
                        .font(.title3)
                }
            }
            .frame(width: 36, height: 28)
            .opacity(isShown ? 1 : 0.4)

            Text(tr(tool.title))
                .foregroundStyle(isShown ? Color.primary : Color.secondary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
