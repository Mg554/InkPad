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
    /// While the toolbar is dragged: where it would dock (the drag itself
    /// stays inside the toolbar, so the page doesn't redraw on every move).
    @State private var dropTarget: ToolbarPlacement?
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
    @State private var areaRequest: AreaRequest?
    /// The notebook beside the book.
    @StateObject private var notebook = NotebookController()
    @AppStorage("notebookWidth") private var notebookWidth: Double = 420
    @State private var notebookDragStart: Double?
    @State private var notebookSend: AreaRequest?
    /// Focus Mode in this note.
    @ObservedObject private var focus = FocusSession.shared
    @State private var showsCompanion = false

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
                    if notebook.isOpen {
                        notebookColumn
                            .transition(.move(edge: .trailing))
                    }
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
                .animation(.snappy(duration: 0.25), value: notebook.isOpen)
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
            canvas.onReadArea = { image, rect in areaRequest = AreaRequest(image: image, rect: rect) }
            canvas.onConcept = { CommandCenter.shared.sheet = .concept($0) }
            if session.snapshot?.pdf != nil {
                canvas.onSendToNotebook = { image, rect in notebookSend = AreaRequest(image: image, rect: rect) }
            }
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
                showsCompanion = false
                isShowingLiving = true
            }
            }
        }
        .inspector(isPresented: $isShowingLiving) {
            sidePanel
                .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
        }
        .modifier(FocusHUD(
            isActive: isFocusingHere,
            canvas: canvas,
            showsCompanion: Binding(get: { showsCompanion && isShowingLiving }, set: { show in
                showsCompanion = show
                showsBookPanel = false
                isShowingLiving = show
            }),
            noteID: noteID,
            end: endFocus
        ))
        .modifier(NotebookSendDialog(request: $notebookSend) { request, asText in
            sendToNotebook(request, asText: asText)
        })
        .modifier(BookSheets(
            noteID: noteID,
            session: session,
            canvas: canvas,
            title: title,
            bookResult: $bookResult,
            isInsertingPages: $isInsertingPages,
            isSendingPages: $isSendingPages,
            areaRequest: $areaRequest
        ))
        .onDisappear {
            LivingNotes.shared.markSeen(noteID)
            // Stopping a recording stores it in the note before the save.
            session.audio.stopAll()
            session.save(thumbnail: true)
            if notebook.isOpen { notebook.close() }
            // Leaving the note ends its focus session; the toolbar comes back.
            if isFocusingHere { endFocus() }
            indexHandwriting()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                // Swift Playgrounds apps can't record in the background.
                session.audio.stopRecording()
                session.audio.pause()
            }
            if scenePhase != .active {
                session.save(thumbnail: true)
                notebook.session.save(thumbnail: true)
            }
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
            DockedToolbarHost(
                edge: edge,
                area: area,
                placement: toolbarPlacement,
                dropTarget: $dropTarget,
                dock: { target in
                    toolbarEdge = target.edge
                    toolbarAlignment = target.alignment
                }
            ) { onMove, onMoveEnded, onMoveCancelled in
                DrawingToolbar(
                    canvas: canvas,
                    pencilOnly: $pencilOnly,
                    edge: edge,
                    onMove: onMove,
                    onMoveEnded: onMoveEnded,
                    onMoveCancelled: onMoveCancelled,
                    onHide: { setToolbarHidden(true) }
                ) {
                    insertMenu
                }
            }
        }
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
        if showsCompanion {
            FocusCompanionView(noteID: noteID, pageText: currentPageText)
        } else if showsBookPanel {
            BookPanel(session: session, canvas: canvas, noteID: noteID) { result in
                bookResult = result
            }
        } else {
            LivingPanel(noteID: noteID, tab: $livingTab)
        }
    }

    // MARK: Focus Mode

    private var isFocusingHere: Bool { focus.isActive && focus.noteID == noteID }

    private func startFocus() {
        // A session in another note ends first.
        if focus.isActive { focus.end(strokes: 0, concepts: [], workspace: workspace) }
        focus.toolbarWasHidden = isToolbarHidden
        setToolbarHidden(true)
        isShowingPages = false
        if notebook.isOpen { notebook.close() }
        showsBookPanel = false
        showsCompanion = true
        isShowingLiving = true
        focus.start(title: title, noteID: noteID, strokes: canvas.drawing?.strokes.count ?? 0, workspace: workspace)
        focus.sawPage(canvas.currentPage, in: noteID)
        if !focus.isActive {
            showsCompanion = false
            isShowingLiving = false
            setToolbarHidden(focus.toolbarWasHidden)
        }
    }

    private func endFocus() {
        let related = LivingNotes.shared.related(to: noteID, store: store, limit: 5)
        var keys: [String] = []
        for item in related {
            for key in item.shared where !keys.contains(key) { keys.append(key) }
        }
        let concepts = keys.prefix(6).map { LivingNotes.shared.display(of: $0) }
        focus.end(strokes: canvas.drawing?.strokes.count ?? 0, concepts: concepts, workspace: workspace)
        showsCompanion = false
        isShowingLiving = false
        setToolbarHidden(focus.toolbarWasHidden)
    }

    /// The text of the page being read: the book page, or the handwriting read so far.
    private func currentPageText() -> String {
        if let pdf = session.snapshot?.pdf?.pdfDocument, let metadata = session.metadata {
            let pages = metadata.resolvedPages(pdfPageCount: pdf.pageCount)
            let page = canvas.currentPage
            if pages.indices.contains(page), case let .pdf(index) = pages[page] {
                return pdf.page(at: index)?.string ?? ""
            }
        }
        return store.recognizedText[noteID] ?? ""
    }

    // MARK: Notebook

    private var notebookColumn: some View {
        HStack(spacing: 0) {
            // Drag to make the notebook wider or narrower.
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 1)
                .overlay {
                    Capsule()
                        .fill(Color(uiColor: .tertiaryLabel))
                        .frame(width: 5, height: 44)
                }
                .frame(width: 14)
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { value in
                        let start = notebookDragStart ?? notebookWidth
                        notebookDragStart = start
                        notebookWidth = min(max(start - Double(value.translation.width), 280), 820)
                    }
                    .onEnded { _ in notebookDragStart = nil })
            NotebookPane(notebook: notebook, session: notebook.session, bookCanvas: canvas, pencilOnly: pencilOnly) {
                notebook.close()
            }
            .frame(width: CGFloat(notebookWidth))
        }
    }

    private func openNotebook() {
        notebook.open(book: session, bookID: noteID, store: store)
    }

    private func sendToNotebook(_ request: AreaRequest, asText: Bool) {
        openNotebook()
        let page = notebook.layoutPage(containing: request.rect)
        Task {
            // A notebook opened just now needs a moment to show its canvas.
            try? await Task.sleep(for: .milliseconds(300))
            if asText {
                await notebook.sendText(of: request.image, fromLayoutPage: page)
            } else {
                await notebook.send(image: request.image, fromLayoutPage: page)
            }
        }
    }

    private func openBookPanel() {
        showsCompanion = false
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
            PaletteItem(id: "ink-focus", title: isFocusingHere ? "End Focus Mode" : "Focus Mode", subtitle: "Hide the tools, time the session, study companion beside the page",
                        systemImage: "scope", tint: .green, section: .thisNote, keywords: ["focus", "تركيز", "deep work"]) {
                if isFocusingHere { endFocus() } else { startFocus() }
            },
            PaletteItem(id: "ink-notebook", title: "Notebook Beside the Book", subtitle: "Write notes next to the book, a page for each chapter",
                        systemImage: "book.pages", tint: .brown, section: .thisNote, keywords: ["notebook", "notes", "دفتر", "ملاحظات"]) {
                openNotebook()
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
                        openNotebook()
                    } label: {
                        Label("Notebook Beside the Book", systemImage: "book.pages")
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
                Button {
                    if notebook.isOpen { notebook.close() } else { openNotebook() }
                } label: {
                    Label("Notebook", systemImage: notebook.isOpen ? "book.pages.fill" : "book.pages")
                }
            }

            Button {
                if isFocusingHere { endFocus() } else { startFocus() }
            } label: {
                Label(isFocusingHere ? "End Focus" : "Focus Mode", systemImage: "scope")
            }
            .tint(isFocusingHere ? Color.green : Color.inkAccent)

            if workspace.flowTimer?.phase == .working {
                Button {
                    CommandCenter.shared.sheet = .catchDistraction
                } label: {
                    Label("Catch a Distraction", systemImage: "tray.and.arrow.down")
                }
                .tint(.orange)
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
    @Binding var areaRequest: AreaRequest?

    func body(content: Content) -> some View {
        content
            .sheet(item: $areaRequest) { request in
                AreaTextSheet(request: request, noteID: noteID) { text, rect in
                    canvas.placeText(text, below: rect)
                }
                .environmentObject(store)
            }
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

/// Lasso › Send to Notebook: as a picture or as text.
private struct NotebookSendDialog: ViewModifier {
    @Binding var request: AreaRequest?
    let send: (AreaRequest, Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Send to Notebook", isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }), titleVisibility: .visible) {
            Button("As a Picture") {
                if let request { send(request, false) }
                request = nil
            }
            Button("As Text (Read on This iPad)") {
                if let request { send(request, true) }
                request = nil
            }
            Button("Cancel", role: .cancel) { request = nil }
        } message: {
            Text("With the book's page number, on the notebook page you're on.")
        }
    }
}

/// While focusing in a note: a small timer, catch a distraction, the
/// companion, and End; then the wrap-up.
private struct FocusHUD: ViewModifier {
    let isActive: Bool
    @ObservedObject var canvas: CanvasController
    @Binding var showsCompanion: Bool
    let noteID: UUID
    let end: () -> Void
    @EnvironmentObject private var workspace: WorkspaceStore

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isActive { hud.transition(.move(edge: .top).combined(with: .opacity)) }
            }
            .animation(.snappy, value: isActive)
            .onChange(of: canvas.currentPage) {
                FocusSession.shared.sawPage(canvas.currentPage, in: noteID)
            }
    }

    private var hud: some View {
        HStack(spacing: 14) {
            Image(systemName: "scope").foregroundStyle(.green)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Flowmodoro.clock(FocusSession.shared.elapsed(at: context.date)))
                    .font(.headline.monospacedDigit())
            }
            Divider().frame(height: 22)
            Button {
                CommandCenter.shared.sheet = .catchDistraction
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .accessibilityLabel("Catch a Distraction")
            Button {
                showsCompanion.toggle()
            } label: {
                Image(systemName: showsCompanion ? "lightbulb.fill" : "lightbulb")
            }
            .accessibilityLabel("Study Companion")
            Button("End", role: .destructive, action: end)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // Solid enough to read over the page's text.
        .background(Color(uiColor: .systemBackground).opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(Color.green.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(.top, 8)
    }
}

/// The docked drawing toolbar while it is dragged: follows the finger
/// without redrawing the page, lifts a little, then glides with a spring
/// into its new place before it docks there.
private struct DockedToolbarHost<Bar: View>: View {
    let edge: ToolbarEdge
    let area: CGSize
    let placement: ToolbarPlacement
    @Binding var dropTarget: ToolbarPlacement?
    let dock: (ToolbarPlacement) -> Void
    @ViewBuilder let bar: (
        _ onMove: @escaping (DragGesture.Value) -> Void,
        _ onMoveEnded: @escaping (DragGesture.Value) -> Void,
        _ onMoveCancelled: @escaping () -> Void
    ) -> Bar

    @State private var drag: CGSize = .zero
    @State private var frame: CGRect = .zero
    @State private var isDragging = false

    var body: some View {
        bar(moved, ended, cancelled)
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.frame(in: .named(ToolbarPlacement.coordinateSpace)), initial: true) { _, newFrame in
                        if drag == .zero { frame = newFrame }
                    }
                }
            }
            .scaleEffect(isDragging ? 1.03 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: isDragging ? 18 : 0, y: isDragging ? 8 : 0)
            .offset(drag)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
            .padding(ToolbarPlacement.margin)
            .frame(
                maxWidth: edge.isVertical ? nil : .infinity,
                maxHeight: edge.isVertical ? .infinity : nil,
                alignment: placement.frameAlignment
            )
    }

    private func target(for value: DragGesture.Value) -> ToolbarPlacement {
        ToolbarPlacement.drop(at: value.location, translation: value.translation, toolbarFrame: frame, from: placement, in: area)
    }

    private func moved(_ value: DragGesture.Value) {
        // Follows the finger exactly, with no animation lag.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            drag = value.translation
            isDragging = true
        }
        let next = target(for: value)
        // The page redraws only when the dock outline moves.
        if next != dropTarget { dropTarget = next }
    }

    /// The system cut the drag off (a call, a sheet, a busy moment): no
    /// end comes, so the toolbar springs back instead of staying stuck.
    private func cancelled() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard isDragging else { return }
            isDragging = false
            dropTarget = nil
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { drag = .zero }
        }
    }

    private func ended(_ value: DragGesture.Value) {
        let next = target(for: value)
        dropTarget = nil
        isDragging = false
        guard next != placement, frame != .zero else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { drag = .zero }
            return
        }
        // Glide to where it will dock: the same shape on the same orientation,
        // or its middle onto the new spot when it turns upright or flat.
        let sameShape: Bool = next.edge.isVertical == edge.isVertical
        let landing: CGRect
        if sameShape {
            landing = next.dockedFrame(barSize: frame.size, in: area)
        } else {
            let turned = CGSize(width: frame.height, height: frame.width)
            landing = next.dockedFrame(barSize: turned, in: area)
        }
        let delta = CGSize(width: landing.midX - frame.midX, height: landing.midY - frame.midY)
        // Docks as soon as it reaches its place, not after the spring's last wobble.
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84), completionCriteria: .logicallyComplete) {
            drag = delta
        } completion: {
            if sameShape {
                // Already in place: dock without any visible jump.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    dock(next)
                    drag = .zero
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    dock(next)
                    drag = .zero
                }
            }
        }
    }
}
