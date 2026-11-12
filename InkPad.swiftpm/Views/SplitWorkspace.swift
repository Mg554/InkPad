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

    var isOpen: Bool { session != nil }

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
                withAnimation(.snappy) { split.showsPages.toggle() }
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
                Button {
                    withAnimation(.snappy) { split.swapped.toggle() }
                } label: {
                    Label("Swap Sides", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    withAnimation(.snappy) { split.vertical.toggle() }
                } label: {
                    Label(split.vertical ? "Side by Side" : "Top and Bottom", systemImage: split.vertical ? "rectangle.split.2x1" : "rectangle.split.1x2")
                }
                Toggle(isOn: Binding(get: { split.syncsScroll }, set: { on in
                    split.syncsScroll = on
                })) {
                    Label("Scroll Together", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    withAnimation(.snappy) { split.maximized = split.maximized == .other ? nil : .other }
                } label: {
                    Label(split.maximized == .other ? "Show Both" : "Make This Side Full", systemImage: "arrow.up.left.and.arrow.down.right")
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
                withAnimation(.snappy) { split.close(beside: mainID) }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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

/// Two views sharing the space, side by side or one above the other, with
/// a divider to drag. `fraction` is the first view's share.
struct SplitStack<First: View, Second: View>: View {
    let vertical: Bool
    @Binding var fraction: Double
    /// The second view comes first (left or top).
    let swapped: Bool
    /// 1 shows only the first, 2 only the second, nil both.
    let only: Int?
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { proxy in
            let total: CGFloat = vertical ? proxy.size.height : proxy.size.width
            let divider: CGFloat = only == nil ? 14 : 0
            let available: CGFloat = max(total - divider, 1)
            let share: CGFloat = only == 1 ? 1 : only == 2 ? 0 : CGFloat(fraction)
            let firstSize: CGFloat = available * share
            let secondSize: CGFloat = available - firstSize
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                if swapped {
                    pane(second(), size: secondSize, total: proxy.size)
                    handle(total: available)
                    pane(first(), size: firstSize, total: proxy.size)
                } else {
                    pane(first(), size: firstSize, total: proxy.size)
                    handle(total: available)
                    pane(second(), size: secondSize, total: proxy.size)
                }
            }
        }
    }

    @ViewBuilder
    private func pane<Content: View>(_ content: Content, size: CGFloat, total: CGSize) -> some View {
        if size > 1 {
            content
                .frame(width: vertical ? total.width : size, height: vertical ? size : total.height)
                .clipped()
        }
    }

    @ViewBuilder
    private func handle(total: CGFloat) -> some View {
        if only == nil {
            ZStack {
                Rectangle().fill(Color(uiColor: .separator))
                    .frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
                Capsule()
                    .fill(Color(uiColor: .tertiaryLabel))
                    .frame(width: vertical ? 44 : 5, height: vertical ? 5 : 44)
            }
            .frame(width: vertical ? nil : 14, height: vertical ? 14 : nil)
            .frame(maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity)
            .background(Color(uiColor: .systemBackground))
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { value in
                    let start = dragStart ?? fraction
                    dragStart = start
                    let moved: CGFloat = vertical ? value.translation.height : value.translation.width
                    let delta = Double(moved / max(total, 1))
                    let next = swapped ? start - delta : start + delta
                    fraction = min(max(next, 0.2), 0.8)
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityLabel("Resize")
        }
    }
}
