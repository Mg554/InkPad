import SwiftUI

/// A detailed row for the list view.
struct NoteRow: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            preview
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if note.isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Text(verbatim: note.title)
                        .font(.headline)
                        .lineLimit(1)
                    if note.favorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 8) {
                    if let folderID = note.folderID, let folder = store.folder(folderID) {
                        Label { Text(verbatim: folder.name) } icon: { Image(systemName: "folder") }
                    }
                    let tags = store.tags(of: note)
                    if !tags.isEmpty {
                        Text(verbatim: tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                            .foregroundStyle(.teal)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            if note.hasAudio == true {
                Image(systemName: "waveform").foregroundStyle(.secondary)
            }
            Text(pagesText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(note.modifiedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .task(id: note.modifiedAt) {
            if !note.isText, note.cover == nil {
                thumbnail = await store.cardThumbnail(for: note.id, modifiedAt: note.modifiedAt)
            }
        }
    }

    private var pagesText: String {
        if note.isText { return tr("Text") }
        let count: Int = note.pageCount ?? 1
        return count == 1 ? tr("1 page") : trMessage("\(count) pages")
    }

    @ViewBuilder
    private var preview: some View {
        if let cover = note.cover {
            NoteCoverView(cover: cover, title: "")
        } else if note.isText {
            ZStack {
                Color.white
                Image(systemName: "doc.text").foregroundStyle(.purple)
            }
        } else if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
            Color.white
        }
    }
}

/// The column titles of the list view; tapping one sorts by it.
struct NoteListHeader: View {
    @Binding var sort: NoteSort

    var body: some View {
        HStack(spacing: 14) {
            column("Name", sortsBy: .name)
                .padding(.leading, 58)
            Spacer()
            column("Pages", sortsBy: .pages)
                .frame(width: 64, alignment: .trailing)
            column("Edited", sortsBy: .edited)
                .frame(width: 150, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func column(_ title: LocalizedStringKey, sortsBy option: NoteSort) -> some View {
        Button {
            sort = option
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sort == option {
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .foregroundStyle(sort == option ? Color.inkAccent : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Makes or edits a smart collection.
struct CollectionEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var collection: SmartCollection
    @State private var limitDays = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $collection.name)
                }
                Section {
                    Picker("Kind", selection: $collection.kind) {
                        ForEach(SmartCollection.Kind.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    Picker("Tag", selection: Binding(
                        get: { collection.tag ?? "" },
                        set: { collection.tag = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Any Tag").tag("")
                        ForEach(store.allTags, id: \.self) { tag in
                            Text(verbatim: "#" + tag).tag(tag)
                        }
                    }
                    Toggle("Edited Recently", isOn: $limitDays)
                    if limitDays {
                        Stepper(value: Binding(
                            get: { collection.editedWithinDays ?? 7 },
                            set: { collection.editedWithinDays = $0 }
                        ), in: 1...365) {
                            Text("In the last \(collection.editedWithinDays ?? 7) days")
                        }
                    }
                    Toggle("Has Audio", isOn: $collection.needsAudio)
                    Toggle("Has Unfinished Tasks", isOn: $collection.needsOpenTasks)
                    Toggle("Favorites Only", isOn: $collection.onlyFavorites)
                } header: {
                    Text("Rules")
                } footer: {
                    Text("A note joins when it matches every rule you set. The collection updates itself.")
                }
                Section {
                    Text("\(matchingCount) notes match now")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Smart Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !limitDays { collection.editedWithinDays = nil }
                        if collection.name.trimmingCharacters(in: .whitespaces).isEmpty { collection.name = tr("Collection") }
                        store.saveCollection(collection)
                        dismiss()
                    }
                }
            }
            .onAppear { limitDays = collection.editedWithinDays != nil }
        }
    }

    private var matchingCount: Int {
        var rules = collection
        if !limitDays { rules.editedWithinDays = nil }
        return store.notes.filter { store.matches($0, collection: rules) }.count
    }
}
