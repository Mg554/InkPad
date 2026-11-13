import SwiftUI
import UniformTypeIdentifiers

struct NotesGridView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    let scope: LibraryScope
    let openNote: (UUID) -> Void

    @State private var searchText = ""
    @State private var prompt: NamePrompt?
    @State private var isImportingPDF = false
    @State private var isShowingTemplates = false
    @State private var slidesNote: NoteSummary?
    @State private var studyNote: NoteSummary?
    @State private var reminderRequest: NoteReminderRequest?
    @State private var historyNote: NoteSummary?
    @State private var coverNote: NoteSummary?
    /// The note whose cover is swinging open.
    @State private var openingID: UUID?
    /// Select mode: tap notes to pick them, then act on all at once.
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmsDelete = false
    @State private var collapsedFolders: Set<UUID> = []
    @State private var isOrganizing = false
    /// Open Beside…: the note to open, waiting for the second one.
    @State private var besideNote: NoteSummary?
    @AppStorage(NoteSort.storageKey) private var sortRaw = NoteSort.edited.rawValue
    @AppStorage(LibraryLayout.storageKey) private var layoutRaw = LibraryLayout.grid.rawValue

    private var sort: NoteSort { NoteSort(rawValue: sortRaw) ?? .edited }
    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRaw) ?? .grid }
    private var sortBinding: Binding<NoteSort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }

    private var arrangement: (pinned: [NoteSummary], others: [NoteSummary]) {
        store.arranged(visibleNotes, sort: sort, scope: scope)
    }

    private var visibleNotes: [NoteSummary] {
        let notes = store.notes(in: scope)
        guard !searchText.isEmpty else { return notes }
        return notes.filter { store.matches($0, search: searchText) }
    }

    private var title: String {
        switch scope {
        case .allNotes: "All Notes"
        case .unfiled: "Unfiled"
        case .planner: "Planner"
        case .expenses: "Expenses"
        case .mindMaps: "Mind Maps"
        case .slides: "Slides"
        case .study: "Study"
        case .flowmodoro: "Flowmodoro"
        case .reminders: "Reminders"
        case .graph: "Graph"
        case .pdfTools: "PDF Tools"
        case .gps: "Knowledge GPS"
        case .favorites: "Favorites"
        case let .builtIn(collection): collection.title
        case let .collection(id): store.collections.first(where: { $0.id == id })?.name ?? "Collection"
        case let .tag(tag): "#\(tag)"
        case let .folder(id): store.folder(id)?.name ?? "Folder"
        }
    }

    private var targetFolderID: UUID? {
        switch scope {
        case let .folder(id): return id
        case .allNotes, .unfiled, .planner, .expenses, .mindMaps, .slides, .study, .flowmodoro, .reminders, .graph, .pdfTools, .gps, .tag,
             .favorites, .builtIn, .collection: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if searchText.isEmpty {
                    quickActions
                        .padding([.horizontal, .top], 24)
                }
                if visibleNotes.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Notes" : "No Results",
                        systemImage: searchText.isEmpty ? "square.and.pencil" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Create a note or import a PDF." : "")
                    )
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
                }
                let arranged = arrangement
                if layout.isShape {
                    notesLayout(arranged.pinned + arranged.others, reorderable: false)
                } else {
                if !arranged.pinned.isEmpty {
                    sectionTitle("Pinned", systemImage: "pin.fill")
                    notesLayout(arranged.pinned, reorderable: false)
                    if !arranged.others.isEmpty {
                        sectionTitle("Notes", systemImage: "square.grid.2x2")
                    }
                }
                notesLayout(arranged.others, reorderable: sort == .custom && !isSelecting)
                }
                if !searchText.isEmpty {
                    MeaningResults(query: searchText) { hit in
                        if let page = hit.pdfPage {
                            CommandCenter.shared.openNote(hit.noteID, pdfPage: page)
                        } else {
                            openNote(hit.noteID)
                        }
                    }
                }
            }
            .padding(.bottom, isSelecting ? 80 : 0)
        }
        .overlay(alignment: .bottom) {
            if isSelecting { selectionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.snappy, value: isSelecting)
        .onChange(of: scope) {
            isSelecting = false
            selection = []
        }
        .confirmationDialog(
            trMessage("Delete \(selection.count) notes?"),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                withAnimation {
                    for id in selection { store.deleteNote(id) }
                }
                endSelecting()
            }
        } message: {
            Text("They stay in Recently Deleted for 30 days.")
        }
        .themedBackground()
        .navigationTitle(tr(title))
        .searchable(text: $searchText, prompt: "Search titles, text, handwriting and #tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting { endSelecting() } else { isSelecting = true }
                }
                .disabled(visibleNotes.isEmpty && !isSelecting)
            }
            ToolbarItem(placement: .primaryAction) {
                arrangeMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    templateButtons
                    Button {
                        isShowingTemplates = true
                    } label: {
                        Label("More Templates…", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button {
                        createTextNote(template: nil)
                    } label: {
                        Label("Text Note", systemImage: "doc.text")
                    }
                    Menu {
                        ForEach(store.templates) { template in
                            Button(tr(template.name)) { createTextNote(template: template) }
                        }
                    } label: {
                        Label("Text Note from Template", systemImage: "doc.on.clipboard")
                    }
                    Divider()
                    Button {
                        isImportingPDF = true
                    } label: {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("New", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $isShowingTemplates) {
            TemplateGallery(
                title: "New Note",
                applyTitle: "Create",
                paper: ThemeSettings.current.paperForNewNotes ? ThemeSettings.current.paper : .white
            ) { template, paper in
                if let note = store.createNote(in: targetFolderID, template: template, paper: paper) {
                    openNote(note.id)
                }
            }
        }
        .sheet(isPresented: $isImportingPDF) {
            DocumentPicker(contentTypes: [.pdf]) { urls in
                importPDFs(urls)
            }
            .ignoresSafeArea()
        }
        .namePrompt($prompt)
        .sheet(isPresented: $isOrganizing) {
            OrganizeLibraryView()
                .environmentObject(store)
        }
        .sheet(item: $besideNote) { note in
            NotePickerSheet(excluding: note.id, title: "Open Beside") { other in
                CommandCenter.shared.openNote(note.id, beside: other)
            }
            .environmentObject(store)
        }
        .sheet(item: $coverNote) { note in
            CoverEditor(note: note)
                .environmentObject(store)
        }
        .sheet(item: $historyNote) { note in
            NoteHistoryView(note: note)
                .environmentObject(store)
        }
        .sheet(item: $reminderRequest) { request in
            ReminderEditor(draft: request.draft())
                .environmentObject(store)
        }
        .sheet(item: $studyNote) { note in
            StudyView(sources: [note.id], isSheet: true)
                .environmentObject(store)
                .environmentObject(workspace)
        }
        .fullScreenCover(item: $slidesNote) { note in
            DeckGeneratorView(sources: [note.id])
                .environmentObject(store)
                .environmentObject(workspace)
        }
    }

    // MARK: Layout

    private var gridColumns: [GridItem] {
        let range = ThemeSettings.current.cardSize.range
        return [GridItem(.adaptive(minimum: range.min, maximum: range.max), spacing: 24)]
    }

    @ViewBuilder
    private func notesLayout(_ notes: [NoteSummary], reorderable: Bool) -> some View {
        switch layout {
        case .grid, .list:
            cardsOrRows(notes, reorderable: reorderable)
        case .icons:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 110), spacing: 16)], spacing: 20) {
                ForEach(notes) { note in
                    item(note, reorderable: reorderable) { NoteIcon(note: note) }
                }
            }
            .padding(24)
        case .compact:
            VStack(spacing: 0) {
                ForEach(notes) { note in
                    item(note, reorderable: reorderable) { NoteCompactRow(note: note) }
                    Divider().padding(.leading, 44)
                }
            }
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        case .bubbles:
            BubbleField(notes: notes) { note in
                item(note, reorderable: false) { NoteBubble(note: note) }
            }
        case .circle:
            SpinningCircle(notes: notes, title: tr(title)) { note in
                item(note, reorderable: false) { NoteBubble(note: note).scaleEffect(0.75) }
            }
        case .tree:
            treeView(notes)
        case .shelf:
            shelfView(notes)
        case .timeline:
            timelineView(notes)
        }
    }

    @ViewBuilder
    private func cardsOrRows(_ notes: [NoteSummary], reorderable: Bool) -> some View {
        if layout == .list {
            VStack(spacing: 0) {
                NoteListHeader(sort: sortBinding)
                Divider()
                ForEach(notes) { note in
                    item(note, reorderable: reorderable) { NoteRow(note: note) }
                    Divider().padding(.leading, 72)
                }
            }
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 28) {
                ForEach(notes) { note in
                    item(note, reorderable: reorderable) { NoteCard(note: note) }
                }
            }
            .padding(24)
        }
    }

    /// A card or row: opens the note, has its menu, and in Custom Order can
    /// be dragged onto another note to go before it.
    @ViewBuilder
    private func item<Content: View>(_ note: NoteSummary, reorderable: Bool, @ViewBuilder content: () -> Content) -> some View {
        let button = Button {
            if isSelecting {
                if selection.contains(note.id) { selection.remove(note.id) } else { selection.insert(note.id) }
                return
            }
            guard note.cover != nil else {
                openNote(note.id)
                return
            }
            // A cover swings open first.
            openingID = note.id
            Task {
                try? await Task.sleep(for: .milliseconds(330))
                openNote(note.id)
                try? await Task.sleep(for: .milliseconds(400))
                openingID = nil
            }
        } label: {
            content()
                .modifier(CoverOpening(isOpening: openingID == note.id))
                .overlay(alignment: .topLeading) {
                    if isSelecting {
                        let picked = selection.contains(note.id)
                        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(picked ? Color.inkAccent : Color.secondary)
                            .background(Circle().fill(.background).padding(2))
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .opacity(isSelecting && !selection.contains(note.id) ? 0.75 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: note) }
        if reorderable {
            button
                .draggable(note.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first, let moved = UUID(uuidString: first) else { return false }
                    let shown: [UUID] = arrangement.others.map(\.id)
                    withAnimation(.snappy) {
                        store.moveInCustomOrder(moved, before: note.id, shown: shown, scope: scope)
                    }
                    return true
                }
        } else {
            button
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.top, 12)
    }

    /// Sorting and grid or list.
    private var arrangeMenu: some View {
        Menu {
            Picker("Sort By", selection: sortBinding) {
                ForEach(NoteSort.allCases) { option in
                    Label(tr(option.title), systemImage: option.systemImage).tag(option)
                }
            }
            Section {
                Picker("View", selection: $layoutRaw) {
                    ForEach(LibraryLayout.allCases) { option in
                        Label(tr(option.title), systemImage: option.systemImage).tag(option.rawValue)
                    }
                }
            }
            if layout == .bubbles || layout == .circle {
                Section {
                    LibraryMotionMenu(isCircle: layout == .circle)
                }
            }
            if sort == .custom {
                Section {
                    Text("Drag a note onto another to put it before that one.")
                }
            }
            Section {
                Button {
                    isOrganizing = true
                } label: {
                    Label("Organize My Library…", systemImage: "wand.and.stars")
                }
            }
        } label: {
            Label("Sort and View", systemImage: layout == .list ? "list.bullet" : "square.grid.2x2")
        }
    }

    @ViewBuilder
    private func menu(for note: NoteSummary) -> some View {
        Button {
            store.setPinned(!note.isPinned, for: note.id)
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin to Top", systemImage: note.isPinned ? "pin.slash" : "pin")
        }

        Button {
            store.setFavorite(!note.favorite, for: note.id)
        } label: {
            Label(note.favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: note.favorite ? "star.slash" : "star")
        }

        Button {
            if note.locked {
                // Removing the protection needs Face ID too.
                Task {
                    let reason = trMessage("Unlock \(note.title).")
                    switch await NoteLock.authenticate(reason: reason) {
                    case .unlocked:
                        store.setLocked(false, for: note.id)
                        CommandCenter.shared.say("Note unlocked.")
                    case .failed:
                        CommandCenter.shared.say("Locked notes open with Face ID or the passcode.")
                    case .needsPasscode:
                        CommandCenter.shared.say("Set a passcode on this iPad — locked notes open with Face ID or the passcode.")
                    }
                }
            } else {
                store.setLocked(true, for: note.id)
                CommandCenter.shared.say("Note locked.")
            }
        } label: {
            Label(note.locked ? "Unlock Note" : "Lock Note", systemImage: note.locked ? "lock.open" : "lock")
        }

        Button {
            coverNote = note
        } label: {
            Label("Cover…", systemImage: "book.closed")
        }

        if !note.isText {
            Button {
                besideNote = note
            } label: {
                Label("Open Beside…", systemImage: "rectangle.split.2x1")
            }
        }

        Divider()

        Button {
            prompt = NamePrompt(
                title: "Rename Note",
                initialText: note.title,
                confirmTitle: "Rename"
            ) { store.renameNote(note.id, to: $0) }
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            prompt = NamePrompt(
                title: "Tags",
                initialText: (note.tags ?? []).joined(separator: ", "),
                confirmTitle: "Save"
            ) { store.setTags(NoteLinks.parseTagList($0), for: note.id) }
        } label: {
            Label("Tags…", systemImage: "number")
        }

        Menu {
            Button("Unfiled") { store.moveNote(note.id, to: nil) }
                .disabled(note.folderID == nil)
            ForEach(store.folderTree()) { row in
                Button(String(repeating: "    ", count: row.depth) + row.folder.name) {
                    store.moveNote(note.id, to: row.folder.id)
                }
                .disabled(note.folderID == row.folder.id)
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }

        Button {
            slidesNote = note
        } label: {
            Label("Create Slides…", systemImage: "rectangle.on.rectangle.angled")
        }

        Button {
            studyNote = note
        } label: {
            Label("Study with AI…", systemImage: "graduationcap")
        }

        Button {
            historyNote = note
        } label: {
            Label("Earlier Versions…", systemImage: "clock.arrow.circlepath")
        }

        Button {
            reminderRequest = NoteReminderRequest(noteID: note.id, title: note.title)
        } label: {
            Label("Remind Me…", systemImage: "bell")
        }

        AIAccessMenu(
            current: note.aiAccess,
            inherited: store.folderAIAccess(note.folderID)
        ) { store.setAIAccess($0, forNote: note.id) }

        Button(role: .destructive) {
            // Kept in Recently Deleted, so no confirmation is needed.
            withAnimation { store.deleteNote(note.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Select

    private func endSelecting() {
        isSelecting = false
        selection = []
    }

    private var selectionBar: some View {
        let ids = Array(selection)
        let none = ids.isEmpty
        return HStack(spacing: 18) {
            Button(selection.count == visibleNotes.count ? "Select None" : "Select All") {
                if selection.count == visibleNotes.count {
                    selection = []
                } else {
                    selection = Set(visibleNotes.map(\.id))
                }
            }
            Text("\(selection.count) selected")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Divider().frame(height: 24)
            Menu {
                Button("Unfiled") { moveSelected(to: nil) }
                ForEach(store.folderTree()) { row in
                    Button(String(repeating: "    ", count: row.depth) + row.folder.name) { moveSelected(to: row.folder.id) }
                }
            } label: {
                Label("Move", systemImage: "folder")
            }
            .disabled(none)
            Button {
                for id in ids { store.duplicateNote(id) }
                endSelecting()
            } label: {
                Label("Copy", systemImage: "plus.square.on.square")
            }
            .disabled(none)
            Menu {
                Button {
                    for id in ids { store.setFavorite(true, for: id) }
                } label: {
                    Label("Add to Favorites", systemImage: "star")
                }
                Button {
                    for id in ids { store.setFavorite(false, for: id) }
                } label: {
                    Label("Remove from Favorites", systemImage: "star.slash")
                }
                Button {
                    for id in ids { store.setPinned(true, for: id) }
                } label: {
                    Label("Pin to Top", systemImage: "pin")
                }
                Button {
                    for id in ids { store.setPinned(false, for: id) }
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
                Button {
                    prompt = NamePrompt(title: "Add Tags", initialText: "", confirmTitle: "Add") { text in
                        let added = NoteLinks.parseTagList(text)
                        for id in ids {
                            let current: [String] = store.note(id)?.tags ?? []
                            store.setTags(current + added.filter { !current.contains($0) }, for: id)
                        }
                    }
                } label: {
                    Label("Add Tags…", systemImage: "number")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(none)
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(none)
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.bottom, 16)
    }

    private func moveSelected(to folderID: UUID?) {
        withAnimation {
            for id in selection { store.moveNote(id, to: folderID) }
        }
        endSelecting()
    }

    // MARK: Shapes

    /// Folders and notes drawn like `tree` in a terminal.
    private func treeView(_ notes: [NoteSummary]) -> some View {
        let lines = treeLines(notes)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(Color.inkAccent)
                Text(verbatim: tr(title)).font(.system(.body, design: .monospaced).weight(.bold))
                Text("(\(notes.count))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
            ForEach(lines) { line in
                TreeLine(ancestors: line.ancestors, isLast: line.isLast) {
                    switch line.kind {
                    case let .folder(folder):
                        Button {
                            withAnimation(.snappy) {
                                if collapsedFolders.contains(folder.id) { collapsedFolders.remove(folder.id) } else { collapsedFolders.insert(folder.id) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: collapsedFolders.contains(folder.id) ? "folder" : "folder.fill")
                                    .foregroundStyle((folder.color ?? .blue).color)
                                Text(verbatim: folder.name + "/").font(.system(.body, design: .monospaced).weight(.semibold))
                            }
                        }
                        .buttonStyle(.plain)
                    case let .note(note):
                        item(note, reorderable: false) {
                            HStack(spacing: 6) {
                                Image(systemName: note.isText ? "doc.text" : note.hasPDF == true ? "doc.richtext" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(verbatim: note.title).font(.system(.body, design: .monospaced))
                                if note.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private struct TreeEntry: Identifiable {
        enum Kind {
            case folder(Folder)
            case note(NoteSummary)
        }
        let id: String
        let kind: Kind
        let ancestors: [Bool]
        let isLast: Bool
    }

    private func treeLines(_ notes: [NoteSummary]) -> [TreeEntry] {
        var result: [TreeEntry] = []
        let rootFolder: UUID?
        switch scope {
        case let .folder(id): rootFolder = id
        case .allNotes: rootFolder = nil
        default:
            // Other lists have no folders: just the notes.
            for (index, note) in notes.enumerated() {
                result.append(TreeEntry(id: note.id.uuidString, kind: .note(note), ancestors: [], isLast: index == notes.count - 1))
            }
            return result
        }
        addTreeLevel(parent: rootFolder, notes: notes, ancestors: [], into: &result)
        return result
    }

    private func addTreeLevel(parent: UUID?, notes: [NoteSummary], ancestors: [Bool], into result: inout [TreeEntry]) {
        let folders: [Folder] = store.folders
            .filter { $0.parentID == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let here: [NoteSummary] = notes.filter { $0.folderID == parent }
        let total = folders.count + here.count
        var position = 0
        for folder in folders {
            position += 1
            let isLast = position == total
            result.append(TreeEntry(id: folder.id.uuidString, kind: .folder(folder), ancestors: ancestors, isLast: isLast))
            if !collapsedFolders.contains(folder.id) {
                addTreeLevel(parent: folder.id, notes: notes, ancestors: ancestors + [!isLast], into: &result)
            }
        }
        for note in here {
            position += 1
            result.append(TreeEntry(id: note.id.uuidString, kind: .note(note), ancestors: ancestors, isLast: position == total))
        }
    }

    /// Notes as books on wooden shelves.
    private func shelfView(_ notes: [NoteSummary]) -> some View {
        let perShelf = 7
        let shelves: [[NoteSummary]] = stride(from: 0, to: notes.count, by: perShelf).map { start in
            Array(notes[start..<min(start + perShelf, notes.count)])
        }
        return VStack(spacing: 26) {
            ForEach(Array(shelves.enumerated()), id: \.offset) { shelf in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(shelf.element) { note in
                            item(note, reorderable: false) { ShelfBook(note: note) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    ShelfPlank()
                }
            }
        }
        .padding(24)
    }

    /// Notes by month, on a line, newest first.
    private func timelineView(_ notes: [NoteSummary]) -> some View {
        let sorted = notes.sorted { $0.modifiedAt > $1.modifiedAt }
        let calendar = Calendar.current
        var months: [(key: Date, notes: [NoteSummary])] = []
        for note in sorted {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: note.modifiedAt)) ?? note.modifiedAt
            if let last = months.last, last.key == month {
                months[months.count - 1].notes.append(note)
            } else {
                months.append((month, [note]))
            }
        }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(months, id: \.key) { month in
                Text(month.key, format: .dateTime.month(.wide).year())
                    .font(.title3.bold())
                    .padding(.top, 8)
                ForEach(Array(month.notes.enumerated()), id: \.element.id) { entry in
                    item(entry.element, reorderable: false) {
                        TimelineEntry(note: entry.element, isLast: entry.offset == month.notes.count - 1)
                    }
                }
            }
        }
        .padding(24)
    }

    /// Notability-style shortcut cards above the notes.
    private var quickActions: some View {
        HStack(spacing: 16) {
            QuickActionCard(title: "New Note", systemImage: "square.and.pencil", tint: .indigo) {
                createNote(.lined)
            }
            QuickActionCard(title: "Import a File", systemImage: "square.and.arrow.down", tint: .teal) {
                isImportingPDF = true
            }
            QuickActionCard(title: "Find a Template", systemImage: "doc.on.doc", tint: .orange) {
                isShowingTemplates = true
            }
            QuickActionCard(title: "Daily Note", systemImage: "calendar.badge.clock", tint: .purple) {
                openDailyNote()
            }
        }
    }

    @ViewBuilder
    private var templateButtons: some View {
        ForEach(PageTemplate.allCases.filter { $0.section == .basic }) { template in
            Button {
                createNote(template)
            } label: {
                Label("\(template.title) Note", systemImage: template.systemImage)
            }
        }
    }

    private func importPDFs(_ urls: [URL]) {
        var lastImported: NoteSummary?
        for url in urls {
            if let note = store.importPDF(from: url, into: targetFolderID) {
                lastImported = note
            }
            // The picker handed us a temporary copy; the store has its own now.
            try? FileManager.default.removeItem(at: url)
        }
        if urls.count == 1, let lastImported {
            openNote(lastImported.id)
        }
    }

    private func createTextNote(template: TextTemplate?) {
        let title = template.map { "\($0.name) \(Date().formatted(date: .abbreviated, time: .omitted))" } ?? "Untitled"
        if let note = store.createTextNote(titled: title, template: template, in: targetFolderID) {
            openNote(note.id)
        }
    }

    private func openDailyNote() {
        let today = workspace.tasks
            .filter { task in task.status != .done && (task.dueDate.map(Calendar.current.isDateInToday) ?? false) }
            .map(\.title)
        if let note = store.dailyNote(tasks: today) {
            openNote(note.id)
        }
    }

    private func createNote(_ template: PageTemplate) {
        let theme = ThemeSettings.current
        if let note = store.createNote(in: targetFolderID, template: template, paper: theme.paperForNewNotes ? theme.paper : .white) {
            openNote(note.id)
        }
    }
}


private struct QuickActionCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(tr(title))
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.35)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
