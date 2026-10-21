import SwiftUI

struct NoteCard: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                }
            }
            .aspectRatio(PageLayout.pageSize.width / PageLayout.pageSize.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            Text(note.modifiedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .task(id: note.modifiedAt) {
            thumbnail = store.thumbnail(for: note.id)
        }
    }
}
