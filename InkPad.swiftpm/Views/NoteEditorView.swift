import PhotosUI
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var palette: ToolPalette
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.scenePhase) private var scenePhase
    let noteID: UUID

    @StateObject private var session = EditorSession()
    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false
    @State private var isShowingExportOptions = false
    @State private var isShowingTemplates = false
    @AppStorage("showPageSidebar") private var isShowingPages = false
    @State private var isPickingPhoto = false
    @State private var isPickingImageFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var prompt: NamePrompt?
    @AppStorage("pencilOnly") private var pencilOnly = true
    @AppStorage("toolbarEdge") private var toolbarEdge: ToolbarEdge = .top
    @AppStorage("toolbarAlignment") private var toolbarAlignment: ToolbarAlignment = .center
    @AppStorage("toolbarHidden") private var isToolbarHidden = false
    /// While the toolbar is dragged: how far, and where it would dock.
    @State private var toolbarDrag: CGSize = .zero
    @State private var dropTarget: ToolbarPlacement?
    /// The docked toolbar's frame in the editor area, before any drag.
    @State private var toolbarFrame: CGRect = .zero
    @State private var recordingToDelete: AudioRecording?
    @State private var slidesRequest: SlidesRequest?
    @State private var studyRequest: SlidesRequest?
    /// Lasso › Think (Write → Think → Build).
    @State private var thinkRequest: ThinkRequest?
    @State private var reminderRequest: NoteReminderRequest?
    @State private var isShowingLiving = false
    @State private var livingTab = LivingTab.related
    /// What the side panel shows: Living Notes or the book's chapters.
    @State private var showsBookPanel = false
    @State private var bookResult: BookResult?
    @State private var isInsertingPages = false
    @State private var isSendingPages = false

    private var canvas: CanvasController { session.canvas }
    private var title: String { store.note(noteID)?.title ?? "Note" }
    private var toolbarPlacement: ToolbarPlacement {
        ToolbarPlacement(edge: toolbarEdge, alignment: toolbarAlignment)
    }

    var body: some View {
        Group {
            if let content = session.initialContent, let background = session.background {
                HStack(spacing: 0) {
                    canvasArea(content: content, background: background)
                    if isShowingPages, let snapshot = session.snapshot {
                        Divider()
                        PageSidebar(
                            canvas: canvas,
                            content: snapshot,
                            revision: session.snapshotRevision,
                            background: background,
                            insertPage: { session.insertPage(after: $0) },
                            deletePage: { session.deletePage(at: $0) },
                            movePage: { session.movePage(from: $0, to: $1) }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.snappy(duration: 0.25), value: isShowingPages)
            } else if let loadError = session.loadError {
                ContentUnavailableView(
                    "Could Not Open Note",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .overlay {
            if isExporting {
                ProgressView("Exporting…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .namePrompt($prompt)
        .paletteNoteCommands(noteID) { paletteCommands }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: file.urls)
        }
        .sheet(isPresented: $isShowingExportOptions) {
            ExportOptionsView(pageCount: canvas.pageCount, currentPage: canvas.currentPage) { options in
                export(options)
            }
        }
        .sheet(isPresented: $isShowingTemplates) {
            TemplateGallery(
                template: session.metadata?.template ?? .lined,
                paper: session.metadata?.paperColor ?? .white
            ) { template, paper in
                session.updateMetadata {
                    $0.template = template
                    $0.paperColor = paper == .white ? nil : paper
                }
            }
        }
        .sheet(isPresented: $isPickingImageFile) {
            DocumentPicker(contentTypes: [.image]) { urls in
                for url in urls {
                    if let data = try? Data(contentsOf: url) { insertImage(data) }
                    try? FileManager.default.removeItem(at: url)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    insertImage(data)
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(recordingToDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { recordingToDelete != nil },
                set: { if !$0 { recordingToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: recordingToDelete
        ) { recording in
            Button("Delete Recording", role: .destructive) {
                session.deleteRecording(recording.id)
            }
        } message: { _ in
            Text("The audio is deleted. What you wrote stays.")
        }
        .fullScreenCover(item: $slidesRequest) { request in
            DeckGeneratorView(sources: [noteID], liveContent: [noteID: request.content])
                .environmentObject(store)
                .environmentObject(workspace)
        }
        .sheet(item: $studyRequest) { request in
            StudyView(sources: [noteID], liveContent: [noteID: request.content], isSheet: true)
                .environmentObject(store)
                .environmentObject(workspace)
        }
        .sheet(item: $reminderRequest) { request in
            ReminderEditor(draft: request.draft())
                .environmentObject(store)
        }
        .sheet(item: $thinkRequest) { request in
            ThinkView(noteID: noteID, text: request.text) { markdown, title in
                canvas.placeText(TextBoxStyle.attributed(markdown: markdown, title: title), below: request.anchor)
            }
                .environmentObject(store)
                .environmentObject(workspace)
        }
        .task {
            session.load(noteID: noteID, store: store)
            canvas.onThink = { text, rect in thinkRequest = ThinkRequest(text: text, anchor: rect) }
            canvas.livingNoteID = noteID
            canvas.onConcept = { CommandCenter.shared.sheet = .concept($0) }
            canvas.onRemind = { text in
                let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                reminderRequest = NoteReminderRequest(noteID: noteID, title: title.isEmpty ? self.title : title)
            }
        }
        .overlay {
            FloatingPlacement(key: "livingBubble", x: 0.05, y: 0.92) {
            LivingBubble(noteID: noteID, isText: false) { tab in
                livingTab = tab
                showsBookPanel = false
                isShowingLiving = true
            }
            }
        }
        .inspector(isPresented: $isShowingLiving) {
            sidePanel
                .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
        }
        .modifier(BookSheets(
            noteID: noteID,
            session: session,
            canvas: canvas,
            title: title,
            bookResult: $bookResult,
            isInsertingPages: $isInsertingPages,
            isSendingPages: $isSendingPages
        ))
        .onDisappear {
            LivingNotes.shared.markSeen(noteID)
            // Stopping a recording stores it in the note before the save.
            session.audio.stopAll()
            session.save(thumbnail: true)
            indexHandwriting()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                // Swift Playgrounds apps can't record in the background.
                session.audio.stopRecording()
                session.audio.pause()
            }
            if scenePhase != .active { session.save(thumbnail: true) }
        }
    }

    /// The page, with the toolbar docked on whichever edge it was dragged to.
    /// Docked toolbars push the page aside rather than cover it.
    private func canvasArea(content: NoteContent, background: NoteBackground) -> some View {
        GeometryReader { proxy in
            NoteCanvas(
                initialContent: content,
                background: background,
                pencilOnly: pencilOnly,
                controller: canvas,
                palette: palette
            )
            .ignoresSafeArea(edges: isToolbarDocked(at: .bottom) ? [] : .bottom)
            .overlay(alignment: .top) {
                AudioPlaybackBar(
                    audio: session.audio,
                    noteID: noteID,
                    recordings: session.recordings,
                    open: { session.openRecording($0) },
                    rename: { renameRecording($0) },
                    share: { shareRecording($0) },
                    delete: { recordingToDelete = $0 }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                PageNavigator(canvas: canvas) { isShowingPages.toggle() }
                    .padding(16)
            }
            .safeAreaInset(edge: .top, spacing: 0) { dockedToolbar(.top, area: proxy.size) }
            .safeAreaInset(edge: .bottom, spacing: 0) { dockedToolbar(.bottom, area: proxy.size) }
            .safeAreaInset(edge: .leading, spacing: 0) { dockedToolbar(.leading, area: proxy.size) }
            .safeAreaInset(edge: .trailing, spacing: 0) { dockedToolbar(.trailing, area: proxy.size) }
            .overlay {
                if let dropTarget {
                    ToolbarDropPreview(placement: dropTarget)
                }
            }
            .overlay(alignment: toolbarPlacement.frameAlignment) {
                if isToolbarHidden {
                    showToolbarButton
                }
            }
        }
        .coordinateSpace(name: ToolbarPlacement.coordinateSpace)
    }

    private func isToolbarDocked(at edge: ToolbarEdge) -> Bool {
        !isToolbarHidden && toolbarEdge == edge
    }

    @ViewBuilder
    private func dockedToolbar(_ edge: ToolbarEdge, area: CGSize) -> some View {
        if isToolbarDocked(at: edge) {
            DrawingToolbar(
                canvas: canvas,
                pencilOnly: $pencilOnly,
                edge: edge,
                onMove: { value in
                    toolbarDrag = value.translation
                    dropTarget = dropPlacement(for: value, in: area)
                },
                onMoveEnded: { value in
                    let target = dropPlacement(for: value, in: area)
                    withAnimation(.snappy(duration: 0.3)) {
                        toolbarEdge = target.edge
                        toolbarAlignment = target.alignment
                        toolbarDrag = .zero
                        dropTarget = nil
                    }
                },
                onHide: { setToolbarHidden(true) }
            ) {
                insertMenu
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.frame(in: .named(ToolbarPlacement.coordinateSpace)), initial: true) { _, frame in
                        if toolbarDrag == .zero { toolbarFrame = frame }
                    }
                }
            }
            .offset(toolbarDrag)
            .padding(ToolbarPlacement.margin)
            .frame(
                maxWidth: edge.isVertical ? nil : .infinity,
                maxHeight: edge.isVertical ? .infinity : nil,
                alignment: toolbarPlacement.frameAlignment
            )
        }
    }

    private func dropPlacement(for drag: DragGesture.Value, in area: CGSize) -> ToolbarPlacement {
        ToolbarPlacement.drop(
            at: drag.location,
            translation: drag.translation,
            toolbarFrame: toolbarFrame,
            from: toolbarPlacement,
            in: area
        )
    }

    /// Brings a hidden toolbar back, from where it was docked.
    private var showToolbarButton: some View {
        Button {
            setToolbarHidden(false)
        } label: {
            Image(systemName: "pencil.tip.crop.circle")
                .font(.title2)
                .padding(10)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .padding(10)
        .accessibilityLabel("Show Toolbar")
    }

    @ViewBuilder
    private var sidePanel: some View {
        if showsBookPanel {
            BookPanel(session: session, canvas: canvas, noteID: noteID) { result in
                bookResult = result
            }
        } else {
            LivingPanel(noteID: noteID, tab: $livingTab)
        }
    }

    private func openBookPanel() {
        showsBookPanel = true
        isShowingLiving = true
    }

    /// This note's commands in Command Anywhere (⌘K).
    private var paletteCommands: [PaletteItem] {
        [
            PaletteItem(id: "ink-chapters", title: "Chapters & Bookmarks", subtitle: "Outline, bookmarks, reading progress, chapter mind maps",
                        systemImage: "book", tint: .brown, section: .thisNote, keywords: ["book", "outline", "فصول", "كتاب", "فهرس"]) {
                openBookPanel()
            },
            PaletteItem(id: "ink-insert-pages", title: "Insert Pages from Another PDF…", systemImage: "doc.on.doc", section: .thisNote,
                        keywords: ["pdf", "pages", "صفحات", "ادراج"]) {
                isInsertingPages = true
            },
            PaletteItem(id: "ink-send-pages", title: "Send Pages to a New Note…", systemImage: "doc.badge.plus", section: .thisNote,
                        keywords: ["extract", "pages", "قص", "صفحات"]) {
                isSendingPages = true
            },
            PaletteItem(id: "ink-study", title: "Study This with AI…", subtitle: "Flashcards, quizzes, summary, chat", systemImage: "graduationcap",
                        tint: .blue, section: .thisNote, keywords: ["flashcards", "quiz", "summary", "بطاقات", "اختبار", "لخص"]) {
                session.save(thumbnail: false)
                studyRequest = session.currentContent().map { SlidesRequest(content: $0) }
            },
            PaletteItem(id: "ink-slides", title: "Create Slides from This…", systemImage: "rectangle.on.rectangle.angled", tint: .orange,
                        section: .thisNote, keywords: ["presentation", "شرائح", "عرض"]) {
                slidesRequest = session.currentContent().map { SlidesRequest(content: $0) }
            },
            PaletteItem(id: "ink-export", title: "Export as PDF", systemImage: "square.and.arrow.up", tint: .green, section: .thisNote,
                        keywords: ["share", "pdf", "تصدير", "مشاركة"]) {
                export(PDFExportOptions())
            },
            PaletteItem(id: "ink-export-as", title: "Export as…", systemImage: "square.and.arrow.up.on.square", tint: .green, section: .thisNote,
                        keywords: ["pages", "password", "تصدير"]) {
                isShowingExportOptions = true
            },
            PaletteItem(id: "ink-add-page", title: "Add a Page", systemImage: "doc.badge.plus", section: .thisNote, keywords: ["page", "صفحة"]) {
                session.insertPage(after: canvas.currentPage)
            },
            PaletteItem(id: "ink-paper", title: "Paper & Template…", systemImage: "doc.richtext", section: .thisNote,
                        keywords: ["lined", "grid", "background", "ورق", "قالب"]) {
                isShowingTemplates = true
            },
            PaletteItem(id: "ink-pages", title: isShowingPages ? "Hide Pages" : "Show Pages", systemImage: "sidebar.right", section: .thisNote,
                        keywords: ["thumbnails", "صفحات"]) {
                isShowingPages.toggle()
            },
            PaletteItem(id: "ink-toolbar", title: isToolbarHidden ? "Show Toolbar" : "Hide Toolbar", systemImage: "eye", section: .thisNote,
                        keywords: ["tools", "ادوات"]) {
                setToolbarHidden(!isToolbarHidden)
            },
            PaletteItem(id: "ink-ruler", title: "Ruler", systemImage: "ruler", section: .thisNote, keywords: ["مسطرة"]) {
                canvas.isRulerActive.toggle()
            },
            PaletteItem(id: "ink-rename", title: "Rename This Note…", systemImage: "pencil", section: .thisNote, keywords: ["اعادة تسمية"]) {
                prompt = NamePrompt(title: "Rename Note", initialText: title, confirmTitle: "Rename") { store.renameNote(noteID, to: $0) }
            },
        ]
    }

    private func setToolbarHidden(_ hidden: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            isToolbarHidden = hidden
        }
    }

    private func moveToolbar(to edge: ToolbarEdge) {
        withAnimation(.snappy(duration: 0.3)) {
            toolbarEdge = edge
            toolbarAlignment = .center
            isToolbarHidden = false
        }
    }

    // MARK: Menus

    @ViewBuilder
    private var insertMenu: some View {
        Button {
            isPickingPhoto = true
        } label: {
            Label("Photo", systemImage: "photo")
        }
        Button {
            isPickingImageFile = true
        } label: {
            Label("Image from Files", systemImage: "folder")
        }
        Button {
            palette.select(.text)
            canvas.applyTool()
        } label: {
            Label("Text Box", systemImage: "textformat")
        }
        Divider()
        Button {
            session.insertPage(after: canvas.currentPage)
        } label: {
            Label("Add Page", systemImage: "doc.badge.plus")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            RecordButton(audio: session.audio) { session.startRecording() }
                .disabled(session.metadata == nil)
            if !session.recordings.isEmpty {
                Menu {
                    ForEach(session.recordings) { recording in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { session.openRecording(recording) }
                        } label: {
                            Label("\(recording.title) · \(AudioClock.string(recording.duration))", systemImage: "waveform")
                        }
                    }
                } label: {
                    Label("Recordings", systemImage: "waveform")
                }
            }

            Button {
                session.save(thumbnail: false)
                studyRequest = session.currentContent().map { SlidesRequest(content: $0) }
            } label: {
                Label("Study with AI", systemImage: "graduationcap")
            }
            .disabled(session.metadata == nil)

            UndoRedoButtons(canvas: canvas)

            Button {
                export(PDFExportOptions())
            } label: {
                Label("Quick Export", systemImage: "square.and.arrow.up")
            }
            .disabled(session.metadata == nil || isExporting)

            Menu {
                Section {
                    Button {
                        export(PDFExportOptions())
                    } label: {
                        Label("Quick Export (PDF, All Pages)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isShowingExportOptions = true
                    } label: {
                        Label("Export as…", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Section {
                    Button {
                        slidesRequest = session.currentContent().map { SlidesRequest(content: $0) }
                    } label: {
                        Label("Create Slides from This Note…", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                Section {
                    Button {
                        openBookPanel()
                    } label: {
                        Label("Chapters & Bookmarks", systemImage: "book")
                    }
                    Button {
                        isInsertingPages = true
                    } label: {
                        Label("Insert Pages from Another PDF…", systemImage: "doc.on.doc")
                    }
                    Button {
                        isSendingPages = true
                    } label: {
                        Label("Send Pages to a New Note…", systemImage: "doc.badge.plus")
                    }
                }
                Section {
                    Button {
                        setToolbarHidden(!isToolbarHidden)
                    } label: {
                        Label(isToolbarHidden ? "Show Toolbar" : "Hide Toolbar", systemImage: isToolbarHidden ? "eye" : "eye.slash")
                    }
                    Menu {
                        ForEach(ToolbarEdge.allCases) { edge in
                            Button {
                                moveToolbar(to: edge)
                            } label: {
                                Label(edge.title, systemImage: edge.systemImage)
                            }
                        }
                    } label: {
                        Label("Move Toolbar", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                }
                Section {
                    Button {
                        isShowingTemplates = true
                    } label: {
                        Label("Template Settings", systemImage: "doc.richtext")
                    }
                    Button {
                        session.insertPage(after: canvas.currentPage)
                    } label: {
                        Label("Add Page After This One", systemImage: "doc.badge.plus")
                    }
                }
                Section {
                    Button {
                        prompt = NamePrompt(
                            title: "Rename Note",
                            initialText: title,
                            confirmTitle: "Rename"
                        ) { store.renameNote(noteID, to: $0) }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    if let note = store.note(noteID) {
                        Text("Edited \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(session.metadata == nil)

            if session.metadata?.pdfFile != nil {
                Button {
                    openBookPanel()
                } label: {
                    Label("Chapters & Bookmarks", systemImage: "book")
                }
            }

            Button {
                isShowingPages.toggle()
            } label: {
                Label("Pages", systemImage: "sidebar.right")
            }
            .disabled(session.metadata == nil)
        }
    }

    // MARK: Actions

    private func export(_ options: PDFExportOptions) {
        guard !isExporting, let content = session.currentContent() else { return }
        session.save(thumbnail: false)
        isExporting = true
        let noteTitle = title
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PDFExporter.export(content, title: noteTitle, options: options) }
            }.value
            isExporting = false
            switch result {
            case let .success(url):
                exportedFile = ExportedFile(url: url)
            case let .failure(error):
                store.errorMessage = "Could not export the PDF: \(error.localizedDescription)"
            }
        }
    }

    /// Reads the handwriting again after changes, so search and AI study find it.
    private func indexHandwriting() {
        guard session.wasEdited, let content = session.currentContent() else { return }
        Task {
            _ = await NoteTexts.text(of: noteID, store: store, live: content, refresh: true)
        }
    }

    private func renameRecording(_ recording: AudioRecording) {
        prompt = NamePrompt(
            title: "Rename Recording",
            initialText: recording.title,
            confirmTitle: "Rename"
        ) { session.renameRecording(recording.id, to: $0) }
    }

    private func shareRecording(_ recording: AudioRecording) {
        if let url = store.exportedAudioURL(recording, of: noteID) {
            exportedFile = ExportedFile(url: url)
        }
    }

    private func insertImage(_ data: Data) {
        Task {
            guard let added = await store.addImage(data, to: noteID),
                  let directory = session.imageDirectory,
                  let image = UIImage(contentsOfFile: directory.appendingPathComponent(added.file).path)
            else { return }
            canvas.insertImage(file: added.file, image: image, pixelSize: added.size)
        }
    }
}

/// "Create Slides" or "Study with AI" opened from the editor, with the note
/// as it is now (including ink not saved yet).
private struct SlidesRequest: Identifiable {
    let id = UUID()
    let content: NoteContent
}

/// Observes the canvas directly so undo state updates without re-rendering the editor.
private struct UndoRedoButtons: View {
    @ObservedObject var canvas: CanvasController

    var body: some View {
        Button {
            canvas.undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!canvas.canUndo)

        Button {
            canvas.redo()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!canvas.canRedo)
    }
}

/// The sheets of the book tools in a note: chapter mind maps and concept
/// graphs, inserting pages from another PDF, and sending pages to a new note.
private struct BookSheets: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    let noteID: UUID
    @ObservedObject var session: EditorSession
    @ObservedObject var canvas: CanvasController
    let title: String
    @Binding var bookResult: BookResult?
    @Binding var isInsertingPages: Bool
    @Binding var isSendingPages: Bool

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $bookResult) { result in
                resultView(result)
                    .environmentObject(store)
                    .environmentObject(workspace)
            }
            .sheet(isPresented: $isInsertingPages) {
                InsertPagesSheet(afterPage: canvas.currentPage) { pages, document in
                    try session.insertPDFPages(pages, from: document, after: canvas.currentPage)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $isSendingPages) {
                if let current = session.currentContent() {
                    SendPagesSheet(content: current, title: title, folderID: store.note(noteID)?.folderID, currentPage: canvas.currentPage)
                        .environmentObject(store)
                }
            }
    }

    @ViewBuilder
    private func resultView(_ result: BookResult) -> some View {
        switch result {
        case let .mindMap(id):
            NavigationStack {
                MindMapEditor(mapID: id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { bookResult = nil }
                        }
                    }
            }
        case let .conceptGraph(title, graph, first, last):
            ConceptGraphView(title: title, graph: graph) { concept in
                pages(mentioning: concept, from: first, to: last)
            } goToPage: { page in
                let pages = session.snapshot?.metadata.resolvedPages(pdfPageCount: session.snapshot?.pdf?.pageCount ?? 0) ?? []
                if let index = PDFToolKit.layoutIndex(ofPDFPage: page, in: pages) {
                    canvas.scrollToPage(index)
                }
            }
        }
    }

    private func pages(mentioning concept: String, from first: Int, to last: Int) -> [Int] {
        guard let document = session.snapshot?.pdf?.pdfDocument else { return [] }
        return (first...last).filter { index in
            document.page(at: index)?.string?.localizedCaseInsensitiveContains(concept) ?? false
        }
    }
}
