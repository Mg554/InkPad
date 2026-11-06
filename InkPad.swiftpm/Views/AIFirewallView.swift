import SwiftUI

/// Notes and folders that are never sent to an AI service, and a way to
/// add more.
struct AIFirewallView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var search = ""

    private var matchingNotes: [NoteSummary] {
        let all = store.notes(in: .allNotes)
        guard !search.isEmpty else { return all }
        return all.filter { store.matches($0, search: search) }
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("Hidden notes are never sent to an AI service: not to chat, flashcards, quizzes, Smart Notes or slides, and not to Apple Intelligence. Slides from them are outlined on this iPad.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }

            if !store.folders.isEmpty {
                Section {
                    ForEach(store.folderTree()) { row in
                        folderToggle(row)
                    }
                } header: {
                    Text("Folders")
                } footer: {
                    Text("Hiding a folder hides every note in it and in its subfolders.")
                }
            }

            Section("Notes") {
                ForEach(matchingNotes) { note in
                    noteToggle(note)
                }
            }
        }
        .searchable(text: $search, prompt: "Search notes")
        .navigationTitle("AI Firewall")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func folderToggle(_ row: FolderRow) -> some View {
        let folder = row.folder
        let inherited = store.isFolderHiddenFromAI(folder.parentID)
        return Toggle(isOn: Binding(
            get: { folder.hiddenFromAI == true || inherited },
            set: { store.setFolderHiddenFromAI(folder.id, $0) }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                    if inherited {
                        Text("Hidden with its parent folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folder.color.tint)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .disabled(inherited)
    }

    private func noteToggle(_ note: NoteSummary) -> some View {
        let inherited = store.isFolderHiddenFromAI(note.folderID)
        return Toggle(isOn: Binding(
            get: { note.hiddenFromAI == true || inherited },
            set: { store.setNoteHiddenFromAI(note.id, $0) }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                    if inherited {
                        Text("Hidden with its folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: note.isText ? "doc.text" : "pencil.and.scribble")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(inherited)
    }
}

/// A small shield shown on notes and folders hidden from AI.
struct HiddenFromAIBadge: View {
    var body: some View {
        Image(systemName: "lock.shield.fill")
            .foregroundStyle(.green)
            .accessibilityLabel("Hidden from AI")
    }
}
