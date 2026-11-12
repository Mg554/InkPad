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
    @ObservedObject var session: EditorSession
    let noteID: UUID
    let content: NoteContent
    let revision: Int
    let background: NoteBackground
    let insertPage: (Int) -> Void
    let deletePage: (Int) -> Void
    let movePage: (Int, Int) -> Void

    @State private var pageToDelete: Int?

    private var deleteTitle: String {
        let number: Int = (pageToDelete ?? 0) + 1
        return "Delete page \(number)?"
    }
    /// The page being dragged to a new place.
    @State private var draggedPage: Int?
    @State private var isSelecting = false
    @State private var selected: Set<Int> = []
    @State private var sizeRequest: SizeRequest?
    @State private var tabPage: Int?
    @State private var movePages: [Int]?

    /// A page size being chosen: for an existing page, or a new one after it.
    private struct SizeRequest: Identifiable {
        let page: Int
        let insertsNew: Bool
        var id: String { "\(page)-\(insertsNew)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isSelecting ? "\(selected.count) selected" : "All Pages")
                    .font(.headline)
                Spacer()
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    selected = []
                }
                .font(.subheadline.weight(.semibold))
            }
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
            if isSelecting {
                Divider()
                selectionBar
            }
        }
        .frame(width: 210)
        .background(.regularMaterial)
        .sheet(item: $sizeRequest) { request in
            PageSizeSheet(
                title: request.insertsNew ? "New Page Size" : "Page Size",
                initial: session.paperSize(at: request.page) ?? PaperSize.standard
            ) { size in
                if request.insertsNew {
                    session.insertPage(after: request.page, size: size)
                } else {
                    session.setPageSize(at: request.page, to: size)
                }
            }
        }
        .sheet(item: Binding(get: { tabPage.map { TabPageID(page: $0) } }, set: { tabPage = $0?.page })) { item in
            PageTabSheet(
                page: item.page,
                existing: session.tab(onPage: item.page),
                save: { session.setTab(onPage: item.page, title: $0, color: $1) },
                remove: { session.removeTab(onPage: item.page) }
            )
        }
        .sheet(item: Binding(get: { movePages.map { MovePagesID(pages: $0) } }, set: { movePages = $0?.pages })) { item in
            MovePagesSheet(session: session, pages: item.pages, currentNoteID: noteID) {
                selected = []
                isSelecting = false
            }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }),
            titleVisibility: .visible,
            presenting: pageToDelete
        ) { index in
            Button("Delete Page", role: .destructive) { deletePage(index) }
        } message: { _ in
            Text("What is written on this page is deleted too. The imported PDF file is not changed.")
        }
    }

    /// Actions for the selected pages.
    private var selectionBar: some View {
        let chosen: [Int] = selected.sorted()
        return HStack(spacing: 18) {
            Button {
                movePages = chosen
            } label: {
                Image(systemName: "arrow.right.doc.on.clipboard")
            }
            .accessibilityLabel("Move to Another Note…")
            Button {
                for page in chosen.sorted(by: >) { session.duplicatePage(at: page) }
                selected = []
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .accessibilityLabel("Duplicate")
            Button(role: .destructive) {
                for page in chosen.sorted(by: >) where session.pageCount > 1 { session.deletePage(at: page) }
                selected = []
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete Pages")
        }
        .font(.title3)
        .disabled(chosen.isEmpty)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func pageRow(_ index: Int) -> some View {
        let isCurrent = index == canvas.currentPage
        let tab: NoteBookmark? = session.tab(onPage: index)
        return VStack(spacing: 6) {
            PageThumbnail(index: index, content: content, background: background, revision: revision)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.inkAccent : Color.secondary.opacity(0.3), lineWidth: isCurrent ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if let tab {
                        Text(verbatim: tab.title)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(tab.color.color, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6))
                            .frame(maxWidth: 110, alignment: .trailing)
                            .padding(.top, 10)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isSelecting {
                        Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, selected.contains(index) ? Color.inkAccent : Color.gray)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Menu {
                        Button {
                            insertPage(index)
                        } label: {
                            Label("Insert Blank Page After", systemImage: "doc.badge.plus")
                        }
                        Button {
                            sizeRequest = SizeRequest(page: index, insertsNew: true)
                        } label: {
                            Label("Insert Page of Another Size…", systemImage: "doc.badge.gearshape")
                        }
                        Button {
                            session.duplicatePage(at: index)
                        } label: {
                            Label("Duplicate Page", systemImage: "plus.square.on.square")
                        }
                        if session.paperSize(at: index) != nil {
                            Button {
                                sizeRequest = SizeRequest(page: index, insertsNew: false)
                            } label: {
                                Label("Page Size…", systemImage: "aspectratio")
                            }
                        }
                        Button {
                            tabPage = index
                        } label: {
                            Label(tab == nil ? "Add Tab…" : "Edit Tab…", systemImage: "bookmark")
                        }
                        Button {
                            movePages = [index]
                        } label: {
                            Label("Move to Another Note…", systemImage: "arrow.right.doc.on.clipboard")
                        }
                        let last = background.layout.pageRects.count - 1
                        Button {
                            movePage(index, index - 1)
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .disabled(index == 0)
                        Button {
                            movePage(index, index + 1)
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .disabled(index == last)
                        Menu {
                            Button("To the Start") { movePage(index, 0) }
                                .disabled(index == 0)
                            Button("To the End") { movePage(index, last) }
                                .disabled(index == last)
                        } label: {
                            Label("Move", systemImage: "arrow.up.arrow.down")
                        }
                        Divider()
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
                .onTapGesture {
                    if isSelecting {
                        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                    } else {
                        canvas.scrollToPage(index)
                    }
                }
                // Long-press and drag a page onto another to move it there.
                .onDrag {
                    draggedPage = index
                    return NSItemProvider(object: "InkPad page \(index)" as NSString)
                }
                .onDrop(of: [.plainText], isTargeted: nil) { _ in
                    defer { draggedPage = nil }
                    guard let source = draggedPage, source != index else { return false }
                    movePage(source, index)
                    return true
                }
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? Color.inkAccent : Color.secondary)
        }
    }
}

private struct TabPageID: Identifiable {
    let page: Int
    var id: Int { page }
}

private struct MovePagesID: Identifiable {
    let pages: [Int]
    var id: String { pages.map(String.init).joined(separator: ",") }
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
