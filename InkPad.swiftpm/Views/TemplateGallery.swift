import SwiftUI

/// Notability-style template picker: paper patterns by section plus paper colors.
struct TemplateGallery: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let applyTitle: String
    let onApply: (PageTemplate, PaperColor) -> Void

    @State private var template: PageTemplate
    @State private var paper: PaperColor

    init(
        title: String = "Templates",
        applyTitle: String = "Apply",
        template: PageTemplate = .lined,
        paper: PaperColor = .white,
        onApply: @escaping (PageTemplate, PaperColor) -> Void
    ) {
        self.title = title
        self.applyTitle = applyTitle
        self.onApply = onApply
        _template = State(initialValue: template)
        _paper = State(initialValue: paper)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    paperColors
                    ForEach(PageTemplate.Section.allCases) { section in
                        Text(section.rawValue)
                            .font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)], spacing: 20) {
                            ForEach(PageTemplate.allCases.filter { $0.section == section }) { item in
                                templateCell(item)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(applyTitle) {
                        onApply(template, paper)
                        dismiss()
                    }
                }
            }
        }
    }

    private var paperColors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paper Color")
                .font(.title3.bold())
            HStack(spacing: 14) {
                ForEach(PaperColor.allCases) { color in
                    Button {
                        paper = color
                    } label: {
                        Circle()
                            .fill(Color(red: color.rgb.red, green: color.rgb.green, blue: color.rgb.blue))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                            .padding(4)
                            .overlay(Circle().stroke(paper == color ? Color.accentColor : Color.clear, lineWidth: 3))
                    }
                    .accessibilityLabel(color.title)
                }
            }
        }
    }

    private func templateCell(_ item: PageTemplate) -> some View {
        Button {
            template = item
        } label: {
            VStack(spacing: 8) {
                TemplatePreview(template: item, paper: paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(template == item ? Color.accentColor : Color.secondary.opacity(0.3),
                                    lineWidth: template == item ? 3 : 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if template == item {
                            Text("SELECTED")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small rendering of a template on the chosen paper.
struct TemplatePreview: View {
    let template: PageTemplate
    let paper: PaperColor
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .aspectRatio(PageLayout.templatePageSize.width / PageLayout.templatePageSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: paper) {
            image = Self.render(template, paper: paper)
        }
    }

    static func render(_ template: PageTemplate, paper: PaperColor) -> UIImage {
        let scale: CGFloat = 0.25
        let pageSize = PageLayout.templatePageSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: pageSize.width * scale, height: pageSize.height * scale), format: format)
            .image { context in
                context.cgContext.scaleBy(x: scale, y: scale)
                TemplateRenderer.drawPage(template, paper: paper, in: CGRect(origin: .zero, size: pageSize), context: context.cgContext)
            }
    }
}
