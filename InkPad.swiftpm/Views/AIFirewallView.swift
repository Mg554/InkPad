import SwiftUI

/// The AI Firewall: for each folder and note, whether AI may read it —
/// any service, only Apple Intelligence on this iPad, or never.
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
                ForEach(AIAccess.allCases) { level in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr(level.title)).font(.headline)
                            Text(trMessage(level.detail))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        AIAccessBadge(access: level)
                    }
                }
            } footer: {
                Text("Protected notes are kept out of chat, flashcards, quizzes, Smart Notes, Think and AI-written slides. Slides from them are outlined on this iPad.")
            }

            if !store.folders.isEmpty {
                Section {
                    ForEach(store.folderTree()) { row in
                        folderRow(row)
                    }
                } header: {
                    Text("Folders")
                } footer: {
                    Text("A folder's level also covers every note in it and in its subfolders.")
                }
            }

            Section("Notes") {
                ForEach(matchingNotes) { note in
                    noteRow(note)
                }
            }
        }
        .searchable(text: $search, prompt: "Search notes")
        .navigationTitle("AI Firewall")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func folderRow(_ row: FolderRow) -> some View {
        let folder = row.folder
        let inherited = store.folderAIAccess(folder.parentID)
        return accessRow(
            title: folder.name,
            icon: Image(systemName: "folder.fill").foregroundStyle(folder.color.tint),
            own: folder.aiAccess,
            inherited: inherited,
            inheritedFrom: "its parent folder"
        ) { store.setAIAccess($0, forFolder: folder.id) }
        .padding(.leading, CGFloat(row.depth) * 18)
    }

    private func noteRow(_ note: NoteSummary) -> some View {
        accessRow(
            title: note.title,
            icon: Image(systemName: note.isText ? "doc.text" : "pencil.and.scribble").foregroundStyle(.secondary),
            own: note.aiAccess,
            inherited: store.folderAIAccess(note.folderID),
            inheritedFrom: "its folder"
        ) { store.setAIAccess($0, forNote: note.id) }
    }

    private func accessRow(
        title: String,
        icon: some View,
        own: AIAccess,
        inherited: AIAccess,
        inheritedFrom: String,
        set: @escaping (AIAccess) -> Void
    ) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(title))
                    if inherited > own {
                        Text("\(inherited.title), set by \(inheritedFrom)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                icon
            }
            Spacer()
            Picker(tr(title), selection: Binding(get: { own }, set: set)) {
                ForEach(AIAccess.allCases) { level in
                    Text(tr(level.title)).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

/// Marks notes and folders the AI Firewall protects.
struct AIAccessBadge: View {
    let access: AIAccess

    var body: some View {
        Image(systemName: access.systemImage)
            .foregroundStyle(access == .never ? Color.green : access == .onDeviceOnly ? Color.teal : Color.secondary)
            .accessibilityLabel("AI Access: \(access.title)")
    }
}

/// "AI Access" in a note or folder's menu.
struct AIAccessMenu: View {
    let current: AIAccess
    /// The level set by the folders above, which this one cannot loosen.
    let inherited: AIAccess
    let set: (AIAccess) -> Void

    var body: some View {
        Menu {
            ForEach(AIAccess.allCases) { level in
                Button {
                    set(level)
                } label: {
                    Label(tr(level.title), systemImage: level == current ? "checkmark" : level.systemImage)
                }
            }
            if inherited > current {
                Text("The folder above sets \(inherited.title).")
            }
        } label: {
            Label("AI Access", systemImage: "lock.shield")
        }
    }
}
