import SwiftUI

/// Deleted notes, kept for `LibraryStore.trashDays` days so a delete can
/// be undone; restore them or delete them for good.
struct RecentlyDeletedView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsEmpty = false
    @State private var noteToErase: NoteSummary?

    var body: some View {
        NavigationStack {
            Group {
                if store.trashedNotes.isEmpty {
                    ContentUnavailableView(
                        "No Deleted Notes",
                        systemImage: "trash",
                        description: Text("Deleted notes stay here for \(LibraryStore.trashDays) days.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.trashedNotes) { note in
                                row(note)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            noteToErase = note
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            store.restoreNote(note.id)
                                        } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(.blue)
                                    }
                                    .contextMenu {
                                        Button {
                                            store.restoreNote(note.id)
                                        } label: {
                                            Label("Restore", systemImage: "arrow.uturn.backward")
                                        }
                                        Button(role: .destructive) {
                                            noteToErase = note
                                        } label: {
                                            Label("Delete Now", systemImage: "trash")
                                        }
                                    }
                            }
                        } footer: {
                            Text("Notes are deleted for good after \(LibraryStore.trashDays) days.")
                        }
                    }
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete All", role: .destructive) { confirmsEmpty = true }
                        .tint(.red)
                        .disabled(store.trashedNotes.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete all \(store.trashedNotes.count) notes for good?",
                isPresented: $confirmsEmpty,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) { store.emptyTrash() }
            } message: {
                Text("This cannot be undone.")
            }
            .confirmationDialog(
                "Delete \"\(noteToErase?.title ?? "")\" for good?",
                isPresented: Binding(get: { noteToErase != nil }, set: { if !$0 { noteToErase = nil } }),
                titleVisibility: .visible,
                presenting: noteToErase
            ) { note in
                Button("Delete Now", role: .destructive) { store.deleteNotePermanently(note.id) }
            } message: { _ in
                Text("This cannot be undone.")
            }
        }
    }

    private func row(_ note: NoteSummary) -> some View {
        HStack(spacing: 14) {
            DeletedNoteThumbnail(note: note)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(note.title))
                    .font(.headline)
                    .lineLimit(1)
                Text(daysLeftText(note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { store.restoreNote(note.id) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private func daysLeftText(_ note: NoteSummary) -> String {
        let days = store.daysLeft(in: note)
        switch days {
        case 0: return "Deleted for good today"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }
}

private struct DeletedNoteThumbnail: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: note.isText ? "doc.text" : "pencil.and.scribble")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        .task(id: note.id) {
            if !note.isText { thumbnail = await store.cardThumbnail(for: note.id, modifiedAt: note.modifiedAt) }
        }
    }
}
