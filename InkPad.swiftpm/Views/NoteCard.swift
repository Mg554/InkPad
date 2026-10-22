import SwiftUI

struct NoteCard: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Color.white
                if note.isText {
                    // Text notes show their opening lines.
                    Text(store.textIndex[note.id]?.preview ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.25))
                        .padding(12)
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                }
            }
            .aspectRatio(PageLayout.templatePageSize.width / PageLayout.templatePageSize.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            let tags = store.tags(of: note)
            if !tags.isEmpty {
                Text(tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.teal)
                    .lineLimit(1)
            }
            Text(note.modifiedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .task(id: note.modifiedAt) {
            if !note.isText { thumbnail = store.thumbnail(for: note.id) }
        }
    }
}
