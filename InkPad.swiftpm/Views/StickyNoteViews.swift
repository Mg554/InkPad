import PencilKit
import SwiftUI

/// An open sticky note: which one, and what it holds now.
struct StickyRequest: Identifiable {
    let id: UUID
    var note: StickyNote
    let page: Int
}

/// A sticky note in a note, with the page it is on.
struct StickyItem: Identifiable {
    let id: UUID
    let note: StickyNote
    let page: Int
}

/// What the owner chose to do with a sticky note.
enum StickyOutcome {
    case save(StickyNote)
    case delete
    case makeTask(StickyNote)
    case turnIntoPage(StickyNote)
}

/// Edits a sticky note: color, typed text and handwriting, group, folding,
/// and turning it into a Planner task or a page.
struct StickyNoteEditor: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let request: StickyRequest
    /// Group names already used in this note.
    let groups: [String]
    let finish: (StickyOutcome) -> Void

    @State private var note = StickyNote()
    @State private var drawing = PKDrawing()
    @State private var groupText = ""

    private var task: PlanTask? {
        guard let taskID = note.taskID else { return nil }
        return workspace.tasks.first(where: { $0.id == taskID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ForEach(StickyNote.Tint.allCases) { tint in
                            Button {
                                note.tint = tint
                            } label: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(tint.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary, lineWidth: note.tint == tint ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(tr(tint.title)))
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Write") {
                    TextField("Type here", text: $note.text, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.custom("Noteworthy-Light", size: 19))
                    VStack(alignment: .leading, spacing: 6) {
                        StickyInkCanvas(drawing: $drawing, tint: note.tint)
                            .frame(width: 300, height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity)
                        HStack {
                            Text("Write with Apple Pencil or a finger.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear Handwriting") { drawing = PKDrawing() }
                                .font(.caption)
                                .disabled(drawing.strokes.isEmpty)
                        }
                    }
                }
                Section {
                    TextField("Group, like Exam or Ideas", text: $groupText)
                    if !groups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(groups, id: \.self) { group in
                                    Button {
                                        groupText = group
                                    } label: {
                                        Text(verbatim: group)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(Color.inkAccent.opacity(groupText == group ? 0.25 : 0.1)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Toggle("Fold to a Small Square", isOn: $note.isFolded)
                } header: {
                    Text("Group")
                }
                Section {
                    if let task {
                        HStack {
                            Label(task.title, systemImage: task.status.systemImage)
                            Spacer()
                            Text(tr(task.status.title)).foregroundStyle(.secondary)
                        }
                        if task.status != .done {
                            Button {
                                workspace.setStatus(.done, for: task.id)
                            } label: {
                                Label("Mark the Task Done", systemImage: "checkmark.circle")
                            }
                        }
                    } else {
                        Button {
                            finish(.makeTask(current))
                            dismiss()
                        } label: {
                            Label("Make a Planner Task", systemImage: "checklist")
                        }
                        .disabled(current.isEmpty)
                    }
                    Button {
                        finish(.turnIntoPage(current))
                        dismiss()
                    } label: {
                        Label("Turn into a Page", systemImage: "doc.badge.plus")
                    }
                    .disabled(current.isEmpty)
                } footer: {
                    Text("A task links back to page \(request.page + 1) of this note. Turning it into a page adds a page after this one with the sticky's writing.")
                }
                Section {
                    Button("Delete Sticky Note", role: .destructive) {
                        finish(.delete)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Sticky Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        finish(.save(current))
                        dismiss()
                    }
                }
            }
            .onAppear {
                note = request.note
                drawing = request.note.drawing ?? PKDrawing()
                groupText = request.note.group ?? ""
            }
        }
    }

    /// The note with the handwriting and group from the form.
    private var current: StickyNote {
        var result = note
        result.ink = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
        let group = groupText.trimmingCharacters(in: .whitespacesAndNewlines)
        result.group = group.isEmpty ? nil : group
        return result
    }
}

/// A small canvas the size of `StickyNote.inkSize`, on the sticky's color.
struct StickyInkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tint: StickyNote.Tint

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor(white: 0.12, alpha: 1), width: 4)
        canvas.isScrollEnabled = false
        canvas.drawing = drawing
        canvas.backgroundColor = tint.uiColor
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.backgroundColor = tint.uiColor
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: StickyInkCanvas

        init(_ parent: StickyInkCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if parent.drawing != canvasView.drawing { parent.drawing = canvasView.drawing }
        }
    }
}

/// Every sticky note in the note, grouped; tap one to go to its page.
struct StickyListView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [StickyItem]
    let open: (UUID, Int) -> Void

    private var groups: [String] {
        var names: [String] = []
        for item in items {
            let name = item.note.group ?? ""
            if !names.contains(name) { names.append(name) }
        }
        return names.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Sticky Notes",
                        systemImage: "note.text",
                        description: Text("Add one from the + menu in the toolbar.")
                    )
                }
                ForEach(groups, id: \.self) { group in
                    Section {
                        ForEach(items.filter { ($0.note.group ?? "") == group }) { item in
                            Button {
                                open(item.id, item.page)
                                dismiss()
                            } label: {
                                row(item.note, page: item.page)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if group.isEmpty {
                            Text("No Group")
                        } else {
                            Text(verbatim: group)
                        }
                    }
                }
            }
            .navigationTitle("Sticky Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ note: StickyNote, page: Int) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(note.tint.color)
                .frame(width: 30, height: 30)
                .overlay {
                    if note.taskID != nil {
                        Image(systemName: "checklist").font(.caption).foregroundStyle(Color.black.opacity(0.55))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                if note.headline.isEmpty {
                    Text("Handwritten note").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: note.headline).lineLimit(1)
                }
                Text("Page \(page + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
