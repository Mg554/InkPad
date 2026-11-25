import PencilKit
import SwiftUI

/// What the editor hands to the find sheet: the note as it is right now, so
/// the page preview shows the same ink the owner sees.
struct FindOnPageRequest: Identifiable {
    var id: UUID { noteID }
    let noteID: UUID
    let content: NoteContent
    let background: NoteBackground
    let initialHits: [OCRHit]
}

/// Finds words the iPad read from handwriting, shows where they are on the
/// page, and jumps to that page when a result is tapped.
struct FindOnPageSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let request: FindOnPageRequest
    let onSelect: (Int) -> Void

    @State private var query = ""
    @State private var hits: [OCRHit] = []
    @State private var selected: OCRHit?
    @State private var preview: UIImage?
    @State private var isReading = false

    private var matching: [OCRHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return hits }
        return hits.filter { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selected != nil {
                    previewArea
                    Divider()
                }
                results
            }
            .navigationTitle(tr("Find on Page"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: tr("Words in your handwriting"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        readAgain()
                    } label: {
                        if isReading {
                            ProgressView()
                        } else {
                            Label(tr("Read Ink"), systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isReading)
                }
            }
            .task { hits = request.initialHits }
        }
    }

    private var previewArea: some View {
        Group {
            if let preview {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                        ForEach(highlighted) { hit in
                            let box = hit.box
                            Rectangle()
                                .fill(Color.yellow.opacity(0.35))
                                .overlay(Rectangle().stroke(Color.orange, lineWidth: 1))
                                .frame(
                                    width: box.width * geometry.size.width,
                                    height: box.height * geometry.size.height
                                )
                                .position(
                                    x: (box.minX + box.width / 2) * geometry.size.width,
                                    y: (box.minY + box.height / 2) * geometry.size.height
                                )
                        }
                    }
                }
                .aspectRatio(preview.size.width / max(preview.size.height, 1), contentMode: .fit)
                .padding(12)
            } else {
                Text(tr("No preview for this page."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private var highlighted: [OCRHit] {
        guard let selected else { return [] }
        return hits.filter { $0.page == selected.page && $0.text == selected.text }
    }

    private var results: some View {
        List {
            if hits.isEmpty {
                Section {
                    Text(tr("No handwriting has been read in this note yet. Tap Read Ink to index it on this iPad."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(matching, id: \.self) { hit in
                Button {
                    selected = hit
                    preview = render(page: hit.page)
                    onSelect(hit.page)
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(Color.inkAccent)
                        VStack(alignment: .leading) {
                            Text(verbatim: hit.text)
                                .font(.body)
                            Text(trMessage("Page {}").replacingOccurrences(of: "{}", with: String(hit.page + 1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func render(page index: Int) -> UIImage? {
        guard request.background.layout.pageRects.indices.contains(index) else { return nil }
        return ThumbnailRenderer.image(
            ofPage: index,
            drawing: request.content.drawing,
            elements: request.content.metadata.elements ?? [],
            imageDirectory: request.content.imageDirectory,
            background: request.background,
            scale: 0.5
        )
    }

    private func readAgain() {
        guard !isReading else { return }
        isReading = true
        let id = request.noteID
        let content = request.content
        Task {
            _ = await NoteTexts.text(of: id, store: store, live: content, refresh: true)
            hits = store.cachedRecognizedHits(for: id)
            isReading = false
        }
    }
}
