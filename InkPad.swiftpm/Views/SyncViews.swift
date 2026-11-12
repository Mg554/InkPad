import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sync: the folder, what syncs, when, the log and conflicts.
struct SyncSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var sync = SyncEngine.shared
    @State private var isPickingFolder = false
    @State private var compared: SyncConflict?

    var body: some View {
        Form {
            Section {
                if sync.isOn {
                    LabeledContent {
                        Text(verbatim: sync.folderName ?? "")
                    } label: {
                        Label("Sync Folder", systemImage: "folder")
                    }
                    Button {
                        sync.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(sync.status == .syncing)
                    SyncStatusLine()
                } else {
                    Button {
                        isPickingFolder = true
                    } label: {
                        Label("Choose a Folder in iCloud Drive…", systemImage: "icloud")
                    }
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Pick the same folder in each copy of InkPad (the Swift Playgrounds copy and the installed app, or another iPad). InkPad keeps an “InkPad Sync” folder inside it. Free, with no account: iCloud Drive moves the files.")
            }
            if sync.isOn {
                Section("What Syncs") {
                    ForEach(SyncPart.allCases) { part in
                        Toggle(isOn: Binding(
                            get: { sync.parts.contains(part) },
                            set: { on in if on { sync.parts.insert(part) } else { sync.parts.remove(part) } }
                        )) {
                            Label(tr(part.title), systemImage: part.systemImage)
                        }
                    }
                }
                Section {
                    Toggle("Sync Automatically", isOn: $sync.automatic)
                    Toggle("Weekly Backup in the Sync Folder", isOn: $sync.weeklyBackup)
                    TextField("This copy's name", text: $sync.deviceName)
                } footer: {
                    Text("Automatic sync runs when InkPad opens, after you leave a note, when it goes to the background and every five minutes. A note that is open is synced after you close it.")
                }
                if !sync.conflicts.isEmpty {
                    Section {
                        ForEach(sync.conflicts) { conflict in
                            Button {
                                compared = conflict
                            } label: {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    VStack(alignment: .leading) {
                                        Text(verbatim: conflict.title).foregroundStyle(Color.primary)
                                        Text(conflict.date, format: .dateTime.day().month().hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("Compare").font(.caption.weight(.semibold))
                                }
                            }
                        }
                    } header: {
                        Text("Both Copies Changed")
                    } footer: {
                        Text("Both versions were kept. Compare them and choose which to keep.")
                    }
                }
                Section("Sync Log") {
                    if sync.log.isEmpty {
                        Text("Nothing yet.").foregroundStyle(.secondary)
                    }
                    ForEach(sync.log.prefix(60)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trMessage(entry.text)).font(.subheadline)
                            Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button {
                        isPickingFolder = true
                    } label: {
                        Label("Choose Another Folder…", systemImage: "folder.badge.gearshape")
                    }
                    Button("Stop Syncing", role: .destructive) { sync.stop() }
                }
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPickingFolder) {
            FolderPicker { url in sync.choose(url) }
                .ignoresSafeArea()
        }
        .sheet(item: $compared) { conflict in
            ConflictCompareView(conflict: conflict)
                .environmentObject(store)
        }
    }
}

/// Last sync, syncing, or what went wrong.
struct SyncStatusLine: View {
    @ObservedObject private var sync = SyncEngine.shared

    var body: some View {
        HStack(spacing: 8) {
            switch sync.status {
            case .off:
                Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                Text("Sync is off")
            case .syncing:
                ProgressView().controlSize(.small)
                Text("Syncing…")
            case let .failed(message):
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
                Text(trMessage(message)).lineLimit(2)
            case .idle:
                Image(systemName: sync.conflicts.isEmpty ? "checkmark.icloud" : "exclamationmark.icloud")
                    .foregroundStyle(sync.conflicts.isEmpty ? Color.green : Color.orange)
                if let last = sync.lastSync {
                    Text("Synced \(last, format: .relative(presentation: .named))")
                } else {
                    Text("Ready to sync")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The sidebar's sync row: status, and tap to sync now.
struct SidebarSyncRow: View {
    @ObservedObject private var sync = SyncEngine.shared

    var body: some View {
        if sync.isOn {
            Button {
                sync.syncNow()
            } label: {
                SyncStatusLine()
            }
            .buttonStyle(.plain)
            .disabled(sync.status == .syncing)
        }
    }
}

/// Picks a folder (in iCloud Drive) for sync.
struct FolderPicker: UIViewControllerRepresentable {
    let picked: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: (URL) -> Void

        init(picked: @escaping (URL) -> Void) {
            self.picked = picked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { picked(url) }
        }
    }
}

/// Two copies of a note side by side: what changed, line by line (like
/// git), an AI summary if wanted, and which to keep.
struct ConflictCompareView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared
    let conflict: SyncConflict

    @State private var lines: [DiffLine] = []
    @State private var isLoading = true
    @State private var summary: String?
    @State private var isAsking = false
    @State private var problem: String?

    private var original: NoteSummary? { store.note(conflict.originalID) }
    private var copy: NoteSummary? { store.note(conflict.copyID) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        side(original, label: "This Copy", tint: .blue)
                        side(copy, label: "Other Copy", tint: .orange)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    if isLoading {
                        ProgressView()
                    } else if lines.allSatisfy({ $0.kind == .same }) {
                        Text("The words are the same; the drawing or layout differs.").foregroundStyle(.secondary)
                    } else {
                        ForEach(lines.filter { $0.kind != .same || lines.count < 40 }) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(line.kind.mark).font(.system(.body, design: .monospaced).weight(.bold))
                                Text(verbatim: line.text).font(.system(.callout, design: .monospaced))
                            }
                            .foregroundStyle(line.kind.color)
                            .listRowBackground(line.kind.color.opacity(line.kind == .same ? 0 : 0.1))
                        }
                    }
                } header: {
                    Text("What Changed")
                } footer: {
                    Text("− only in this copy   + only in the other copy")
                }
                Section {
                    if let summary {
                        Text(summary)
                    }
                    Button {
                        askAI()
                    } label: {
                        Label(isAsking ? "Comparing…" : "Ask AI What Changed", systemImage: "sparkles")
                    }
                    .disabled(isAsking || !ai.isReady)
                    if let problem {
                        Text(trMessage(problem)).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section {
                    Button {
                        keepThis()
                    } label: {
                        Label("Keep This Copy", systemImage: "checkmark.circle")
                    }
                    Button {
                        keepOther()
                    } label: {
                        Label("Keep the Other Copy", systemImage: "arrow.left.arrow.right.circle")
                    }
                    Button {
                        SyncEngine.shared.resolve(conflict)
                        dismiss()
                    } label: {
                        Label("Keep Both", systemImage: "square.on.square")
                    }
                } footer: {
                    Text("The copy you don't keep goes to Recently Deleted.")
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func side(_ note: NoteSummary?, label: LocalizedStringKey, tint: Color) -> some View {
        VStack(spacing: 6) {
            if let note {
                NotePreview(note: note)
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint, lineWidth: 2))
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Text(note.modifiedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Missing").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        guard let original, let copy else {
            isLoading = false
            return
        }
        let mine = await OrganizeAdvisor.quickText(of: original, store: store)
        let theirs = await OrganizeAdvisor.quickText(of: copy, store: store)
        lines = await Task.detached(priority: .userInitiated) { LineDiff.diff(mine, theirs) }.value
        isLoading = false
    }

    private func askAI() {
        guard let client = ai.client(),
              store.mayUseAI(conflict.originalID, onDevice: client.kind.isOnDevice),
              store.mayUseAI(conflict.copyID, onDevice: client.kind.isOnDevice)
        else {
            problem = "The AI Firewall keeps one of these notes on the iPad."
            return
        }
        let changes = lines.filter { $0.kind != .same }.prefix(200).map { $0.kind.mark + " " + $0.text }.joined(separator: "\n")
        isAsking = true
        Task {
            defer { isAsking = false }
            let prompt = [
                "Two copies of the same note were edited separately. Lines starting with − are only in this copy,",
                "lines with + only in the other copy. In a few bullet points, say what each copy has that the other lacks,",
                "and which seems more complete. Use the notes' language.",
                "",
                changes,
            ].joined(separator: "\n")
            do {
                summary = try await client.complete(system: "You compare versions of study notes.", messages: [AIMessage(.user, prompt)])
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func keepThis() {
        store.deleteNote(conflict.copyID)
        SyncEngine.shared.resolve(conflict)
        dismiss()
    }

    private func keepOther() {
        guard let original else { return }
        store.deleteNote(conflict.originalID)
        store.renameNote(conflict.copyID, to: original.title)
        store.moveNote(conflict.copyID, to: original.folderID)
        SyncEngine.shared.resolve(conflict)
        dismiss()
    }
}

/// One line of a comparison.
struct DiffLine: Identifiable, Sendable {
    enum Kind: Sendable {
        case same, removed, added

        var mark: String {
            switch self {
            case .same: " "
            case .removed: "−"
            case .added: "+"
            }
        }

        var color: Color {
            switch self {
            case .same: .secondary
            case .removed: .red
            case .added: .green
            }
        }
    }

    let id: Int
    let kind: Kind
    let text: String
}

/// Line-by-line differences (longest common subsequence), like `git diff`.
enum LineDiff {
    static func diff(_ old: String, _ new: String) -> [DiffLine] {
        let a = Array(lines(old).prefix(1500))
        let b = Array(lines(new).prefix(1500))
        let n = a.count
        let m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var result: [DiffLine] = []
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                result.append(DiffLine(id: result.count, kind: .same, text: a[i]))
                i += 1
                j += 1
            } else if j < m, i == n || table[i][j + 1] >= table[i + 1][j] {
                result.append(DiffLine(id: result.count, kind: .added, text: b[j]))
                j += 1
            } else {
                result.append(DiffLine(id: result.count, kind: .removed, text: a[i]))
                i += 1
            }
        }
        return result
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
