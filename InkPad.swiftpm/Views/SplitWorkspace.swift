import SwiftUI

/// A named pair of notes, opened side by side from the sidebar.
struct SavedWorkspace: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var first: UUID
    var second: UUID
    var vertical: Bool

    init(name: String, first: UUID, second: UUID, vertical: Bool) {
        id = UUID()
        self.name = name
        self.first = first
        self.second = second
        self.vertical = vertical
    }
}

/// What the split workspace remembers: the note last opened beside each
/// note (and whether it was still open), and named workspaces.
@MainActor
final class SplitMemory: ObservableObject {
    static let shared = SplitMemory()

    private struct Saved: Codable {
        var partners: [String: String] = [:]
        var openWith: [String] = []
        var workspaces: [SavedWorkspace] = []
    }

    private static let key = "splitMemory"
    @Published private(set) var workspaces: [SavedWorkspace] = []
    private var partners: [String: String] = [:]
    private var openWith: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            partners = saved.partners
            openWith = Set(saved.openWith)
            workspaces = saved.workspaces
        }
    }

    private func save() {
        let saved = Saved(partners: partners, openWith: Array(openWith), workspaces: workspaces)
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func partner(of id: UUID) -> UUID? {
        partners[id.uuidString].flatMap(UUID.init(uuidString:))
    }

    /// The note beside `id` when it was last closed, if the split was open.
    func openPartner(of id: UUID) -> UUID? {
        openWith.contains(id.uuidString) ? partner(of: id) : nil
    }

    func remember(_ partner: UUID?, beside id: UUID) {
        if let partner {
            partners[id.uuidString] = partner.uuidString
            openWith.insert(id.uuidString)
        } else {
            openWith.remove(id.uuidString)
        }
        save()
    }

    func saveWorkspace(_ workspace: SavedWorkspace) {
        workspaces.removeAll { $0.first == workspace.first && $0.second == workspace.second }
        workspaces.append(workspace)
        save()
    }

    func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        save()
    }
}

/// The second note in the split workspace and how the two share the screen.
@MainActor
final class SplitController: ObservableObject {
    enum Side { case main, other }

    @Published private(set) var session: EditorSession?
    @Published private(set) var otherID: UUID?
    /// The side the toolbar works on: the last one touched.
    @Published var active: Side = .main
    /// The other note on the left (or on top).
    @Published var swapped = false
    @Published var vertical: Bool = UserDefaults.standard.bool(forKey: "splitVertical") {
        didSet { UserDefaults.standard.set(vertical, forKey: "splitVertical") }
    }
    /// The main note's share of the space.
    @Published var fraction: Double = UserDefaults.standard.object(forKey: "splitFraction") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(fraction, forKey: "splitFraction") }
    }
    /// One side made full size for a moment.
    @Published var maximized: Side?
    /// Scroll the other note with the main one (page for page).
    @Published var syncsScroll = false
    /// The other note's pages panel.
    @Published var showsPages = false
    /// Pages apart when scrolling was linked.
    var pageOffset = 0

    // Slide Over: the other note floats above the main one.
    @Published var floating: Bool = UserDefaults.standard.bool(forKey: "splitFloating") {
        didSet { UserDefaults.standard.set(floating, forKey: "splitFloating") }
    }
    /// The floating window's top-left corner; nil until placed.
    @Published var floatOrigin: CGPoint?
    @Published var floatSize: CGSize?
    /// The live drag of the floating window (or of the pane, to swap).
    @Published var windowDrag: CGSize = .zero
    /// Slid off an edge: only a tab shows there.
    @Published var tucked: HorizontalEdge?
    /// The editor's space, measured.
    var container: CGSize = .zero

    var isOpen: Bool { session != nil }

    /// Spring when the owner wants motion, else a short ease.
    static var motion: Animation {
        let smooth: Bool = UserDefaults.standard.object(forKey: SplitPrefs.spring) as? Bool ?? true
        return smooth ? .spring(response: 0.42, dampingFraction: 0.84) : .easeInOut(duration: 0.18)
    }

    enum Arrangement { case sideBySide, topAndBottom, slideOver }

    func arrange(_ arrangement: Arrangement) {
        withAnimation(Self.motion) {
            maximized = nil
            tucked = nil
            switch arrangement {
            case .sideBySide:
                floating = false
                vertical = false
            case .topAndBottom:
                floating = false
                vertical = true
            case .slideOver:
                floating = true
            }
        }
    }

    /// Where the floating window sits in a space of `size`.
    func floatRect(in size: CGSize) -> CGRect {
        let wanted: CGSize = floatSize ?? CGSize(width: min(max(size.width * 0.38, 320), 480), height: size.height * 0.86)
        let width: CGFloat = min(max(wanted.width, 280), max(size.width - 24, 280))
        let height: CGFloat = min(max(wanted.height, 320), max(size.height - 24, 320))
        let origin: CGPoint = floatOrigin ?? CGPoint(x: size.width - width - 14, y: (size.height - height) / 2)
        var x: CGFloat = origin.x + windowDrag.width
        var y: CGFloat = origin.y + windowDrag.height
        y = min(max(y, 8), max(size.height - height - 8, 8))
        if let tucked {
            x = tucked == .trailing ? size.width + 24 : -width - 24
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The floating window let go: thrown off an edge it tucks away, else it
    /// settles on the nearer side.
    func endFloatDrag(translation: CGSize, predicted: CGSize) {
        let size = container
        windowDrag = .zero
        let rect = floatRect(in: size)
        let thrownX: CGFloat = rect.midX + predicted.width
        withAnimation(Self.motion) {
            if thrownX > size.width + rect.width * 0.05 {
                floatOrigin = CGPoint(x: size.width - rect.width - 14, y: rect.minY + translation.height)
                tucked = .trailing
            } else if thrownX < -rect.width * 0.05 {
                floatOrigin = CGPoint(x: 14, y: rect.minY + translation.height)
                tucked = .leading
            } else {
                let movedX: CGFloat = rect.minX + translation.width
                let movedY: CGFloat = rect.minY + translation.height
                let onRight: Bool = movedX + rect.width / 2 > size.width / 2
                floatOrigin = CGPoint(x: onRight ? size.width - rect.width - 14 : 14, y: movedY)
            }
        }
    }

    func untuck() {
        withAnimation(Self.motion) { tucked = nil }
    }

    func resizeFloat(to newSize: CGSize) {
        let maxWidth: CGFloat = max(container.width - 24, 280)
        let maxHeight: CGFloat = max(container.height - 16, 320)
        floatSize = CGSize(width: min(max(newSize.width, 280), maxWidth), height: min(max(newSize.height, 320), maxHeight))
    }

    /// The pane dragged by its bar toward the other side: swap them.
    func endPaneDrag(_ translation: CGSize) {
        let moved: CGFloat = vertical ? translation.height : translation.width
        // The other note sits after the main one unless swapped.
        let towardOther: CGFloat = swapped ? moved : -moved
        withAnimation(Self.motion) {
            windowDrag = .zero
            if towardOther > 110 { swapped.toggle() }
        }
    }

    func open(_ id: UUID, beside mainID: UUID, store: LibraryStore) {
        guard id != mainID, store.note(id) != nil, !(store.note(id)?.isText ?? true) else { return }
        if let session { session.save(thumbnail: true) }
        let fresh = EditorSession()
        fresh.load(noteID: id, store: store)
        if let otherID { SyncEngine.shared.openNotes.remove(otherID) }
        session = fresh
        otherID = id
        SyncEngine.shared.openNotes.insert(id)
        active = .other
        maximized = nil
        tucked = nil
        windowDrag = .zero
        SplitMemory.shared.remember(id, beside: mainID)
    }

    func close(beside mainID: UUID?) {
        session?.audio.stopAll()
        session?.save(thumbnail: true)
        if let otherID { SyncEngine.shared.openNotes.remove(otherID) }
        session = nil
        otherID = nil
        active = .main
        maximized = nil
        tucked = nil
        windowDrag = .zero
        syncsScroll = false
        if let mainID { SplitMemory.shared.remember(nil, beside: mainID) }
    }
}

/// The bar above the note beside: its title, and the split's controls.
struct SplitPaneHeader: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var split: SplitController
    @ObservedObject var canvas: CanvasController
    let mainID: UUID
    let pick: () -> Void
    let saveWorkspace: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(split.active == .other ? Color.inkAccent : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(verbatim: split.otherID.flatMap { store.note($0)?.title } ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button {
                canvas.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canvas.canUndo)
            Button {
                withAnimation(SplitController.motion) { split.showsPages.toggle() }
            } label: {
                Image(systemName: split.showsPages ? "sidebar.right" : "rectangle.grid.1x2")
            }
            .accessibilityLabel("Pages")
            Menu {
                Button {
                    pick()
                } label: {
                    Label("Open Another Note Here…", systemImage: "doc.on.doc")
                }
                WindowArrangeButtons(split: split, side: .other, close: { split.close(beside: mainID) })
                Toggle(isOn: Binding(get: { split.syncsScroll }, set: { on in
                    split.syncsScroll = on
                })) {
                    Label("Scroll Together", systemImage: "arrow.up.arrow.down")
                }
                Divider()
                Button {
                    saveWorkspace()
                } label: {
                    Label("Save as a Workspace…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            Button {
                withAnimation(SplitController.motion) { split.close(beside: mainID) }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .contentShape(Rectangle())
        .gesture(moveGesture)
    }

    /// Dragging the bar moves the floating window, or carries the pane
    /// across to swap sides.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                split.windowDrag = value.translation
            }
            .onEnded { value in
                if split.floating {
                    split.endFloatDrag(translation: value.translation, predicted: value.predictedEndTranslation)
                } else {
                    split.endPaneDrag(value.translation)
                }
            }
    }
}

/// Picks a note (or PDF) to open beside the current one.
struct NotePickerSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let excluding: UUID?
    let title: LocalizedStringKey
    let picked: (UUID) -> Void
    @State private var search = ""

    private var notes: [NoteSummary] {
        let all = store.notes.filter { !$0.isText && $0.id != excluding }
        let found = search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
        return found.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        NavigationStack {
            List(notes) { note in
                Button {
                    picked(note.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        NotePreview(note: note)
                            .frame(width: 34, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: note.title).foregroundStyle(Color.primary)
                            Text(note.modifiedAt, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if note.hasPDF == true { Image(systemName: "doc.richtext").foregroundStyle(.secondary) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search notes and PDFs")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The sidebar's saved workspaces.
struct SidebarWorkspaces: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var memory = SplitMemory.shared

    var body: some View {
        if !memory.workspaces.isEmpty {
            Section("Workspaces") {
                ForEach(memory.workspaces) { workspace in
                    Button {
                        CommandCenter.shared.openNote(workspace.first, beside: workspace.second)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: workspace.name)
                                Text(verbatim: names(workspace))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: workspace.vertical ? "rectangle.split.1x2" : "rectangle.split.2x1")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            memory.deleteWorkspace(workspace.id)
                        } label: {
                            Label("Delete Workspace", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func names(_ workspace: SavedWorkspace) -> String {
        let first = store.note(workspace.first)?.title ?? "?"
        let second = store.note(workspace.second)?.title ?? "?"
        return first + "  ·  " + second
    }
}
