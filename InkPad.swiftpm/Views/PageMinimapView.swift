import PencilKit
import SwiftUI

/// A small overview of every page with the part of the current page on
/// screen marked on it, like a minimap in a code editor. Tap a page to
/// jump to it.
struct PageMinimapView: View {
    @ObservedObject var canvas: CanvasController
    let content: NoteContent
    let background: NoteBackground
    let revision: Int
    /// Hides the overview.
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Overview").font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Close"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(background.layout.pageRects.indices, id: \.self) { index in
                            MinimapPageView(
                                index: index,
                                content: content,
                                background: background,
                                revision: revision,
                                isCurrent: index == canvas.currentPage,
                                viewport: index == canvas.currentPage ? canvas.viewportOnPage : .zero
                            ) {
                                canvas.scrollToPage(index)
                            }
                            .id(index)
                        }
                    }
                    .padding(12)
                }
                .onAppear { proxy.scrollTo(canvas.currentPage, anchor: .center) }
                .onChange(of: canvas.currentPage) {
                    withAnimation { proxy.scrollTo(canvas.currentPage, anchor: .center) }
                }
            }
        }
        .frame(width: 140)
        .frame(maxHeight: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
    }
}

/// One page of the overview: its thumbnail, the viewport on the current
/// page, and its number.
private struct MinimapPageView: View {
    let index: Int
    let content: NoteContent
    let background: NoteBackground
    let revision: Int
    let isCurrent: Bool
    /// The part of the page on screen, as a fraction of the page.
    let viewport: CGRect
    let jump: () -> Void
    @State private var image: UIImage?

    var body: some View {
        let rect = background.layout.pageRects[index]
        Button(action: jump) {
            ZStack {
                Color.white
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .aspectRatio(rect.width / rect.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: Theme.Radius.xs)
                        .stroke(Color.inkAccent, lineWidth: 2)
                }
            }
            .overlay {
                if isCurrent, viewport.width > 0.01, viewport.height > 0.01 {
                    GeometryReader { proxy in
                        let width = proxy.size.width * min(1, viewport.width)
                        let height = proxy.size.height * min(1, viewport.height)
                        let x = min(max(proxy.size.width * viewport.minX, 0), max(proxy.size.width - width, 0))
                        let y = min(max(proxy.size.height * viewport.minY, 0), max(proxy.size.height - height, 0))
                        Rectangle()
                            .fill(Color.inkAccent.opacity(0.18))
                            .overlay(Rectangle().stroke(Color.inkAccent, lineWidth: 1.5))
                            .frame(width: width, height: height)
                            .offset(x: x, y: y)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .task(id: revision) {
            // Rendered off the main thread so the canvas keeps scrolling.
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
                    scale: 0.14
                )
            }.value
        }
    }
}
