import SwiftUI

struct NoteCard: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    /// Locked notes show a lock instead of their contents until they are
    /// unlocked with Face ID (or the passcode).
    private var showsLock: Bool { note.locked && !store.isUnlocked(note.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Color.white
                if showsLock {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let cover = note.cover {
                    NoteCoverView(cover: cover, title: note.title)
                } else if note.isText {
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
            .overlay(alignment: .topTrailing) { badges }

            HStack(spacing: 4) {
                Text(tr(note.title))
                    .font(.headline)
                    .lineLimit(1)
                if store.aiAccess(of: note.id) != .allowed {
                    AIAccessBadge(access: store.aiAccess(of: note.id))
                        .font(.caption)
                }
            }
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
        .task(id: "\(note.id)-\(note.modifiedAt.timeIntervalSince1970)-\(showsLock)") {
            if showsLock { thumbnail = nil; return }
            if !note.isText, note.cover == nil { thumbnail = await store.cardThumbnail(for: note.id, modifiedAt: note.modifiedAt) }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if note.isPinned || note.favorite || showsLock {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill").foregroundStyle(Color.orange)
                }
                if note.favorite {
                    Image(systemName: "star.fill").foregroundStyle(Color.yellow)
                }
                if showsLock {
                    Image(systemName: "lock.fill").foregroundStyle(Color.brown)
                }
            }
            .font(.caption)
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            .padding(6)
        }
    }
}
