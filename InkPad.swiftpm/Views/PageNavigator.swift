import PencilKit
import SwiftUI

/// Current page and page count with previous/next buttons, like Notability's.
struct PageNavigator: View {
    @ObservedObject var canvas: CanvasController
    let showOverview: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button {
                canvas.scrollToPage(canvas.currentPage - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(canvas.currentPage == 0)

            Button(action: showOverview) {
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

/// A grid of all pages; tap one to jump to it.
struct PageOverview: View {
    @Environment(\.dismiss) private var dismiss
    let drawing: PKDrawing
    let background: NoteBackground
    let currentPage: Int
    let selectPage: (Int) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 20)], spacing: 20) {
                        ForEach(background.layout.pageRects.indices, id: \.self) { index in
                            Button {
                                selectPage(index)
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    PageThumbnail(index: index, drawing: drawing, background: background)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3),
                                                        lineWidth: index == currentPage ? 3 : 1)
                                        )
                                    Text("\(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(20)
                }
                .onAppear { proxy.scrollTo(currentPage, anchor: .center) }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct PageThumbnail: View {
    let index: Int
    let drawing: PKDrawing
    let background: NoteBackground
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
        .task {
            image = ThumbnailRenderer.image(ofPage: index, drawing: drawing, background: background, scale: 0.25)
        }
    }
}
