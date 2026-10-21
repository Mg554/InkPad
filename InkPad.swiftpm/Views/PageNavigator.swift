import PencilKit
import SwiftUI

/// Current page and page count with previous/next buttons, like Notability's.
struct PageNavigator: View {
    @ObservedObject var canvas: CanvasController
    /// Shows or hides the page sidebar.
    let togglePages: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button {
                canvas.scrollToPage(canvas.currentPage - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(canvas.currentPage == 0)

            Button(action: togglePages) {
                VStack(spacing: 2) {
                    Text("\(canvas.currentPage + 1)")
                    Divider().frame(width: 28)
                    Text("\(canvas.pageCount)")
                        .foregroundStyle(.secondary)
                }
                .font(.callout.monospacedDigit())
            }
            .accessibilityLabel("Page \(canvas.currentPage + 1) of \(canvas.pageCount)")

            Button {
                canvas.scrollToPage(canvas.currentPage + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(canvas.currentPage >= canvas.pageCount - 1)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .frame(width: 52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}

/// Notability-style page list at the side: thumbnails of every page, the
/// current one highlighted, with insert and delete in each page's menu.
struct PageSidebar: View {
    @ObservedObject var canvas: CanvasController
    let content: NoteContent
    let revision: Int
    let background: NoteBackground
    let insertPage: (Int) -> Void
    let deletePage: (Int) -> Void

    @State private var pageToDelete: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text("All Pages")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(background.layout.pageRects.indices, id: \.self) { index in
                            pageRow(index)
                                .id(index)
                        }
                    }
                    .padding(16)
                }
                .onAppear { proxy.scrollTo(canvas.currentPage, anchor: .center) }
                .onChange(of: canvas.currentPage) {
                    withAnimation { proxy.scrollTo(canvas.currentPage, anchor: .center) }
                }
            }
        }
        .frame(width: 210)
        .background(.regularMaterial)
        .confirmationDialog(
            "Delete page \((pageToDelete ?? 0) + 1)?",
            isPresented: Binding(get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }),
            titleVisibility: .visible,
            presenting: pageToDelete
        ) { index in
            Button("Delete Page", role: .destructive) { deletePage(index) }
        } message: { _ in
            Text("What is written on this page is deleted too. The imported PDF file is not changed.")
        }
    }

    private func pageRow(_ index: Int) -> some View {
        let isCurrent = index == canvas.currentPage
        return VStack(spacing: 6) {
            PageThumbnail(index: index, content: content, background: background, revision: revision)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isCurrent ? 3 : 1)
                )
                .overlay(alignment: .bottomLeading) {
                    Menu {
                        Button {
                            insertPage(index)
                        } label: {
                            Label("Insert Blank Page After", systemImage: "doc.badge.plus")
                        }
                        Button(role: .destructive) {
                            pageToDelete = index
                        } label: {
                            Label("Delete Page", systemImage: "trash")
                        }
                        .disabled(background.layout.pageRects.count <= 1)
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .regularMaterial)
                            .padding(6)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { canvas.scrollToPage(index) }
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
        }
    }
}

private struct PageThumbnail: View {
    let index: Int
    let content: NoteContent
    let background: NoteBackground
    let revision: Int
    @State private var image: UIImage?

    var body: some View {
        let rect = background.layout.pageRects[index]
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .aspectRatio(rect.width / rect.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: revision) {
            // Rendered off the main thread so scrolling the list stays smooth.
            let content = content
            let background = background
            let index = index
            image = await Task.detached(priority: .utility) {
                ThumbnailRenderer.image(
                    ofPage: index,
                    drawing: content.drawing,
                    elements: content.metadata.elements ?? [],
                    imageDirectory: content.imageDirectory,
                    background: background,
                    scale: 0.22
                )
            }.value
        }
    }
}
