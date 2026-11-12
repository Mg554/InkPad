import SwiftUI

/// Picks a page size: a ready-made size in either orientation, or any size in millimeters.
struct PageSizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let initial: PaperSize
    let apply: (PaperSize) -> Void

    @State private var preset: PaperPreset = .a4
    @State private var landscape = false
    @State private var widthMM: Double = 210
    @State private var heightMM: Double = 297

    private static let pointsPerMM: Double = 72 / 25.4

    private var size: PaperSize {
        if preset == .custom {
            let width: Double = max(widthMM, 20) * Self.pointsPerMM
            let height: Double = max(heightMM, 20) * Self.pointsPerMM
            return PaperSize(width: width, height: height)
        }
        let base: PaperSize = preset.size ?? PaperSize.standard
        return landscape ? base.swapped : base
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
                            .aspectRatio(CGFloat(size.width / size.height), contentMode: .fit)
                            .frame(height: 150)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Size") {
                    Picker("Size", selection: $preset) {
                        ForEach(PaperPreset.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    if preset != .custom {
                        Picker("Orientation", selection: $landscape) {
                            Label("Portrait", systemImage: "rectangle.portrait").tag(false)
                            Label("Landscape", systemImage: "rectangle").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if preset == .custom {
                    Section {
                        Stepper(value: $widthMM, in: 20...2000, step: 5) {
                            Text("Width: \(Int(widthMM)) mm")
                        }
                        Stepper(value: $heightMM, in: 20...2000, step: 5) {
                            Text("Height: \(Int(heightMM)) mm")
                        }
                    } header: {
                        Text("Custom Size")
                    } footer: {
                        Text("Every page is shown the same width; its shape follows the size. Exported PDFs use the exact size.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        apply(size)
                        dismiss()
                    }
                }
            }
            .onAppear {
                preset = PaperPreset.matching(initial)
                landscape = initial.isLandscape
                widthMM = (initial.width / Self.pointsPerMM).rounded()
                heightMM = (initial.height / Self.pointsPerMM).rounded()
            }
        }
    }
}

/// Names and colors a page's tab.
struct PageTabSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: Int
    let existing: NoteBookmark?
    let save: (String, FolderColor) -> Void
    let remove: () -> Void

    @State private var name = ""
    @State private var color: FolderColor = .blue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tab name, like Chapter 2", text: $name)
                }
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(FolderColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: color == option ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Button("Remove Tab", role: .destructive) {
                            remove()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Page \(page + 1) Tab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(name, color)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = existing?.title ?? ""
                color = existing?.color ?? .blue
            }
        }
    }
}

/// Tabs down the page's edge: a jump list of the note's tabbed pages.
struct PageTabStrip: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var canvas: CanvasController

    var body: some View {
        let tabs = session.tabs
        if !tabs.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(tabs) { tab in
                        Button {
                            canvas.scrollToPage(tab.page)
                        } label: {
                            Text(verbatim: tab.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(Color.white)
                                .padding(.vertical, 6)
                                .padding(.leading, 10)
                                .padding(.trailing, canvas.currentPage == tab.page ? 14 : 8)
                                .frame(maxWidth: 130, alignment: .leading)
                                .background(tab.color.color.opacity(canvas.currentPage == tab.page ? 1 : 0.75),
                                            in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .animation(.snappy, value: canvas.currentPage)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// Moves or copies pages into another note, keeping the writing editable.
struct MovePagesSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: EditorSession
    let pages: [Int]
    let currentNoteID: UUID
    let finished: () -> Void

    @State private var targetID: UUID?
    @State private var placement = Placement.end
    @State private var afterPage = 1
    @State private var keepCopy = false
    @State private var search = ""
    @State private var working = false
    @State private var problem: String?

    enum Placement: Hashable { case start, end, after }

    private var targets: [NoteSummary] {
        let all = store.notes.filter { !$0.isText && $0.id != currentNoteID }
        let list = search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
        return list.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var sheetTitle: LocalizedStringKey {
        if pages.count == 1 { return keepCopy ? "Copy 1 Page" : "Move 1 Page" }
        return keepCopy ? "Copy \(pages.count) Pages" : "Move \(pages.count) Pages"
    }

    private var targetPageCount: Int {
        guard let targetID else { return 1 }
        return store.note(targetID)?.pageCount ?? 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Search notes", text: $search)
                    ForEach(targets.prefix(40)) { note in
                        Button {
                            targetID = note.id
                        } label: {
                            HStack {
                                Image(systemName: note.hasPDF == true ? "doc.richtext" : "doc")
                                Text(verbatim: note.title).foregroundStyle(Color.primary)
                                Spacer()
                                if targetID == note.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.inkAccent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("To Note")
                }
                Section("Where") {
                    Picker("Where", selection: $placement) {
                        Text("At the Start").tag(Placement.start)
                        Text("At the End").tag(Placement.end)
                        Text("After a Page").tag(Placement.after)
                    }
                    .pickerStyle(.segmented)
                    if placement == .after {
                        Stepper(value: $afterPage, in: 1...max(targetPageCount, 1)) {
                            Text("After page \(afterPage)")
                        }
                    }
                }
                Section {
                    Toggle("Keep the Pages Here Too (Copy)", isOn: $keepCopy)
                } footer: {
                    Text("Handwriting stays editable, with text boxes, images, PDF pages and page sizes.")
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(keepCopy ? "Copy" : "Move") { run() }
                        .disabled(targetID == nil || working || pages.isEmpty)
                }
            }
            .overlay {
                if working {
                    ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Move Pages", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(trMessage(problem ?? ""))
            }
        }
    }

    private func run() {
        guard let targetID, let source = session.currentContent() else { return }
        working = true
        let position: PageTransfer.Position
        switch placement {
        case .start: position = .start
        case .end: position = .end
        case .after: position = .after(afterPage - 1)
        }
        Task {
            defer { working = false }
            do {
                let target = try store.loadContent(for: targetID)
                let lifted = PageTransfer.lift(pages, from: source)
                let updated = try PageTransfer.insert(lifted, from: source, into: target, at: position)
                guard await store.saveContent(updated, for: targetID, thumbnail: true) else { return }
                if let old = target.pdf?.fileURL, updated.metadata.pdfFile != target.metadata.pdfFile {
                    try? FileManager.default.removeItem(at: old)
                }
                if !keepCopy {
                    for page in pages.sorted(by: >) where session.pageCount > 1 {
                        session.deletePage(at: page)
                    }
                }
                let name = store.note(targetID)?.title ?? ""
                CommandCenter.shared.say(trMessage("\(pages.count) pages moved to “\(name)”"))
                finished()
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
