import NaturalLanguage
import SwiftUI

/// Ideas for tidying a note: a better title, a folder (existing or new) and tags.
struct OrganizeSuggestion: Identifiable, Equatable {
    let noteID: UUID
    var title: String?
    var folderID: UUID?
    var newFolder: String?
    var tags: [String]
    var byAI: Bool

    var id: UUID { noteID }
    var isEmpty: Bool { title == nil && folderID == nil && newFolder == nil && tags.isEmpty }
}

/// Suggests titles, folders and tags: on the iPad from the note's words and
/// the library's folders, or by the AI service when the AI Firewall allows
/// the note. Nothing changes until the owner accepts.
@MainActor
final class OrganizeAdvisor: ObservableObject {
    static let shared = OrganizeAdvisor()

    /// Shown in the library after leaving a new note.
    @Published var pending: OrganizeSuggestion?
    private var dismissed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "organizeDismissed") ?? [])

    /// A note still has the name it was made with.
    static func isUntitled(_ note: NoteSummary) -> Bool {
        let title = note.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty || title.hasPrefix("Untitled") || title.hasPrefix("Note ") || title.hasPrefix("Daily Note")
    }

    /// After leaving a note made today that is unfiled or untitled.
    func offer(after id: UUID, store: LibraryStore) async {
        guard let note = store.note(id), !dismissed.contains(id.uuidString),
              Date().timeIntervalSince(note.createdAt) < 86_400,
              note.folderID == nil || Self.isUntitled(note)
        else { return }
        // Let the handwriting be read when leaving the note first.
        try? await Task.sleep(for: .seconds(2))
        let useAI = AISettings.shared.isReady && store.mayUseAI(id, onDevice: AISettings.shared.provider.isOnDevice)
        guard let suggestion = await suggest(for: note, store: store, useAI: useAI), !suggestion.isEmpty else { return }
        pending = suggestion
    }

    func dismiss(_ id: UUID) {
        dismissed.insert(id.uuidString)
        UserDefaults.standard.set(Array(dismissed), forKey: "organizeDismissed")
        if pending?.noteID == id { pending = nil }
    }

    func suggest(for note: NoteSummary, store: LibraryStore, useAI: Bool) async -> OrganizeSuggestion? {
        let text = await Self.quickText(of: note, store: store)
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty || !Self.isUntitled(note) else { return nil }
        if useAI, let made = await aiSuggestion(for: note, text: words, store: store) { return made }
        return localSuggestion(for: note, text: words, store: store)
    }

    /// The note's words without slow reading where possible: kept text,
    /// a PDF's own text, and only then reading the handwriting.
    static func quickText(of note: NoteSummary, store: LibraryStore) async -> String {
        if note.isText { return store.textIndex[note.id]?.text ?? "" }
        if let known = store.recognizedText[note.id] ?? store.cachedRecognizedText(for: note.id), !known.isEmpty { return known }
        if note.hasPDF == true, let content = try? store.loadContent(for: note.id), let document = content.pdf?.pdfDocument {
            var pages: [String] = []
            for index in 0..<min(document.pageCount, 5) {
                if let text = document.page(at: index)?.string { pages.append(text) }
            }
            let joined = pages.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return joined }
        }
        return await NoteTexts.text(of: note.id, store: store)
    }

    // MARK: On the iPad

    private func localSuggestion(for note: NoteSummary, text: String, store: LibraryStore) -> OrganizeSuggestion {
        var suggestion = OrganizeSuggestion(noteID: note.id, title: nil, folderID: nil, newFolder: nil, tags: [], byAI: false)
        if Self.isUntitled(note) { suggestion.title = Self.titleLine(in: text) }
        let mine = Self.keywords(in: note.title + "\n" + text)
        if note.folderID == nil {
            var best: (UUID, Int)?
            let allFolderWords = folderWords(store: store)
            for folder in store.folders {
                let folderWords = allFolderWords[folder.id] ?? []
                let shared = mine.intersection(folderWords).count
                if shared >= 2, shared > (best?.1 ?? 0) { best = (folder.id, shared) }
            }
            suggestion.folderID = best?.0
        }
        let have = Set(note.tags ?? [])
        let textWords = SemanticSearch.words(text)
        for tag in store.allTags where !have.contains(tag) {
            if !SemanticSearch.words(tag).isDisjoint(with: textWords) { suggestion.tags.append(tag) }
            if suggestion.tags.count >= 3 { break }
        }
        if suggestion.tags.isEmpty, let top = Self.rankedKeywords(in: text).first, !have.contains(top) {
            suggestion.tags = [top]
        }
        return suggestion
    }

    /// Each folder's words (its name, its notes' titles and key words), kept a minute.
    private var folderCache: (made: Date, words: [UUID: Set<String>])?

    private func folderWords(store: LibraryStore) -> [UUID: Set<String>] {
        if let folderCache, Date().timeIntervalSince(folderCache.made) < 60 { return folderCache.words }
        var result: [UUID: Set<String>] = [:]
        for folder in store.folders {
            var words = SemanticSearch.words(folder.name)
            for other in store.notes where other.folderID == folder.id {
                words.formUnion(SemanticSearch.words(other.title))
                if let known = store.recognizedText[other.id] ?? store.textIndex[other.id]?.text {
                    words.formUnion(Self.keywords(in: String(known.prefix(3000))))
                }
            }
            result[folder.id] = words
        }
        folderCache = (Date(), result)
        return result
    }

    private static let plainWords: Set<String> = ["note", "notes", "page", "pages", "chapter", "thing", "things", "today", "time"]

    /// The first line that reads like a title.
    static func titleLine(in text: String) -> String? {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#*-•")))
            let count = line.split(separator: " ").count
            if count >= 2, line.count >= 6 {
                return line.count > 50 ? String(line.prefix(50)).trimmingCharacters(in: .whitespaces) + "…" : line
            }
        }
        return nil
    }

    /// Nouns (lemmas) of four or more letters.
    static func keywords(in text: String) -> Set<String> {
        Set(rankedKeywords(in: text, limit: 25))
    }

    static func rankedKeywords(in text: String, limit: Int = 5) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        var counts: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard tag == .noun else { return true }
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? String(text[range])
            let word = lemma.lowercased()
            if word.count >= 4, !plainWords.contains(word) { counts[word, default: 0] += 1 }
            return true
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    // MARK: By AI

    private func aiSuggestion(for note: NoteSummary, text: String, store: LibraryStore) async -> OrganizeSuggestion? {
        guard let client = AISettings.shared.client(), store.mayUseAI(note.id, onDevice: client.kind.isOnDevice) else { return nil }
        let folders = store.folders.map(\.name).joined(separator: ", ")
        let tags = store.allTags.prefix(60).joined(separator: ", ")
        let prompt = [
            "Suggest how to file this note. Answer with JSON only:",
            "{\"title\": \"short title or empty\", \"folder\": \"one existing folder or empty\", \"new_folder\": \"a new folder name or empty\", \"tags\": [\"tag\"]}",
            "Give a title only if the current one is a placeholder. Prefer an existing folder; suggest a new folder only when none fits.",
            "Up to 3 tags, single words, prefer existing tags. Use the note's language.",
            "Current title: \(note.title)",
            "Folders: \(folders.isEmpty ? "none" : folders)",
            "Existing tags: \(tags.isEmpty ? "none" : tags)",
            "",
            "Note:",
            String(text.prefix(4000)),
        ].joined(separator: "\n")
        guard let reply = try? await client.complete(system: "You organize a student's note library.", messages: [AIMessage(.user, prompt)]),
              let json = AIJSON.object(in: reply) else { return nil }
        var suggestion = OrganizeSuggestion(noteID: note.id, title: nil, folderID: nil, newFolder: nil, tags: [], byAI: true)
        if let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty, Self.isUntitled(note) {
            suggestion.title = title
        }
        if note.folderID == nil {
            if let name = json["folder"] as? String, let folder = store.folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                suggestion.folderID = folder.id
            } else if let name = (json["new_folder"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                suggestion.newFolder = name
            }
        }
        let have = Set(note.tags ?? [])
        suggestion.tags = ((json["tags"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty && !have.contains($0) }
        return suggestion
    }

    // MARK: Applying

    struct Parts: OptionSet {
        let rawValue: Int
        static let title = Parts(rawValue: 1)
        static let folder = Parts(rawValue: 2)
        static let tags = Parts(rawValue: 4)
        static let all: Parts = [.title, .folder, .tags]
    }

    func apply(_ suggestion: OrganizeSuggestion, parts: Parts = .all, store: LibraryStore) {
        if parts.contains(.title), let title = suggestion.title { store.renameNote(suggestion.noteID, to: title) }
        if parts.contains(.folder) {
            if let folderID = suggestion.folderID {
                store.moveNote(suggestion.noteID, to: folderID)
            } else if let name = suggestion.newFolder {
                let folder = store.folders.first(where: { $0.name == name && $0.parentID == nil }) ?? store.createFolder(named: name)
                if let folder { store.moveNote(suggestion.noteID, to: folder.id) }
            }
        }
        if parts.contains(.tags), !suggestion.tags.isEmpty {
            let current: [String] = store.note(suggestion.noteID)?.tags ?? []
            store.setTags(current + suggestion.tags.filter { !current.contains($0) }, for: suggestion.noteID)
        }
    }
}

/// The suggestion bar shown in the library after leaving a new note.
struct OrganizeBanner: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var advisor = OrganizeAdvisor.shared

    var body: some View {
        if let suggestion = advisor.pending, let note = store.note(suggestion.noteID) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: suggestion.byAI ? "sparkles" : "wand.and.stars").foregroundStyle(.purple)
                    Text("Tidy “\(note.title)”?").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Button("Not Now") { advisor.dismiss(suggestion.noteID) }.font(.caption)
                }
                SuggestionChips(suggestion: suggestion, store: store) { advisor.dismiss(suggestion.noteID) }
            }
            .padding(14)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Buttons to accept each part of a suggestion.
struct SuggestionChips: View {
    let suggestion: OrganizeSuggestion
    let store: LibraryStore
    let done: () -> Void
    @State private var applied: OrganizeAdvisor.Parts = []

    var body: some View {
        HStack(spacing: 8) {
            if let title = suggestion.title {
                chip(Text("Rename: \(title)"), systemImage: "pencil", part: .title)
            }
            if let folderID = suggestion.folderID, let folder = store.folder(folderID) {
                chip(Text("Move to \(folder.name)"), systemImage: "folder", part: .folder)
            } else if let name = suggestion.newFolder {
                chip(Text("New folder \(name)"), systemImage: "folder.badge.plus", part: .folder)
            }
            if !suggestion.tags.isEmpty {
                chip(Text(verbatim: suggestion.tags.map { "#" + $0 }.joined(separator: " ")), systemImage: "number", part: .tags)
            }
            Spacer(minLength: 0)
            Button {
                OrganizeAdvisor.shared.apply(suggestion, parts: OrganizeAdvisor.Parts.all.subtracting(applied), store: store)
                done()
            } label: {
                Text("Accept All")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .font(.caption)
    }

    private func chip(_ label: Text, systemImage: String, part: OrganizeAdvisor.Parts) -> some View {
        Button {
            OrganizeAdvisor.shared.apply(suggestion, parts: part, store: store)
            applied.insert(part)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: applied.contains(part) ? "checkmark" : systemImage)
                label.lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(applied.contains(part))
    }
}

/// Organize My Library: suggestions for every unfiled or untitled note, and
/// new folders for notes that belong together.
struct OrganizeLibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared
    @State private var suggestions: [OrganizeSuggestion] = []
    @State private var groups: [(name: String, notes: [UUID])] = []
    @State private var isWorking = false
    @State private var progress = ""
    @State private var usesAI = false

    private var candidates: [NoteSummary] {
        store.notes.filter { $0.folderID == nil || OrganizeAdvisor.isUntitled($0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $usesAI) {
                        Label("Use AI where the AI Firewall allows", systemImage: "sparkles")
                    }
                    .disabled(!ai.isReady)
                    Button {
                        Task { await analyze() }
                    } label: {
                        Label(suggestions.isEmpty ? "Find Suggestions" : "Look Again", systemImage: "wand.and.stars")
                    }
                    .disabled(isWorking)
                    if isWorking {
                        HStack { ProgressView(); Text(trMessage(progress)).font(.caption).foregroundStyle(.secondary) }
                    }
                } footer: {
                    Text("\(candidates.count) notes are unfiled or still have their first name. Nothing changes until you accept.")
                }
                if !groups.isEmpty {
                    Section("New Folders") {
                        ForEach(groups, id: \.name) { group in
                            HStack {
                                Label { Text(verbatim: group.name) } icon: { Image(systemName: "folder.badge.plus") }
                                Text("\(group.notes.count) notes").foregroundStyle(.secondary)
                                Spacer()
                                Button("Create") { createGroup(group) }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if !suggestions.isEmpty {
                    Section("Notes") {
                        ForEach(suggestions) { suggestion in
                            if let note = store.note(suggestion.noteID) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(verbatim: note.title).font(.subheadline.weight(.semibold))
                                        if suggestion.byAI { Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple) }
                                    }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        SuggestionChips(suggestion: suggestion, store: store) {
                                            suggestions.removeAll { $0.id == suggestion.id }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Organize My Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { if suggestions.isEmpty { await analyze() } }
        }
    }

    private func analyze() async {
        isWorking = true
        defer { isWorking = false }
        suggestions = []
        var topics: [String: [UUID]] = [:]
        let list = Array(candidates.prefix(40))
        for (index, note) in list.enumerated() {
            progress = trMessage("Reading \(index + 1) of \(list.count)…")
            let useAI = usesAI && store.mayUseAI(note.id, onDevice: ai.provider.isOnDevice)
            if let suggestion = await OrganizeAdvisor.shared.suggest(for: note, store: store, useAI: useAI), !suggestion.isEmpty {
                suggestions.append(suggestion)
                if suggestion.folderID == nil, note.folderID == nil {
                    let text = store.recognizedText[note.id] ?? store.textIndex[note.id]?.text ?? note.title
                    if let topic = OrganizeAdvisor.rankedKeywords(in: note.title + "\n" + text, limit: 1).first {
                        topics[topic, default: []].append(note.id)
                    }
                }
            }
        }
        let existing = Set(store.folders.map { $0.name.lowercased() })
        groups = topics.filter { $0.value.count >= 3 && !existing.contains($0.key) }
            .map { (name: $0.key.capitalized, notes: $0.value) }
            .sorted { $0.notes.count > $1.notes.count }
    }

    private func createGroup(_ group: (name: String, notes: [UUID])) {
        guard let folder = store.createFolder(named: group.name) else { return }
        for id in group.notes { store.moveNote(id, to: folder.id) }
        groups.removeAll { $0.name == group.name }
        suggestions.removeAll { group.notes.contains($0.noteID) && $0.title == nil }
    }
}
