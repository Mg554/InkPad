import SwiftUI

/// A modern to-do list: quick add, sections by day, a checkbox that
/// strikes the task through, steps with progress, swipe to finish, move to
/// tomorrow or delete, and drag to reorder.
struct ToDoListView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: LibraryStore
    /// Opens the full editor.
    let edit: (PlanTask) -> Void
    /// A task just made: scrolled to and lit up.
    @Binding var highlight: UUID?

    @State private var newTitle = ""
    @State private var newDue: QuickDue = .today
    @State private var newPriority: PlanTask.Priority = .medium
    @State private var expanded: Set<UUID> = []
    @State private var stepDrafts: [UUID: String] = [:]
    @AppStorage("todoShowsDone") private var showsDone = false
    @FocusState private var addFocused: Bool

    enum QuickDue: String, CaseIterable, Identifiable {
        case today, tomorrow, someday
        var id: Self { self }
        var title: String {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .someday: "Someday"
            }
        }
        var date: Date? {
            let calendar = Calendar.current
            let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
            switch self {
            case .today: return evening
            case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: evening)
            case .someday: return nil
            }
        }
    }

    private struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let tint: Color
        let tasks: [PlanTask]
    }

    private var groups: [TaskGroup] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let open = workspace.tasks.filter { $0.status != .done }
        let isToday: (PlanTask) -> Bool = { task in task.dueDate.map(calendar.isDateInToday) ?? false }
        let overdue = open.filter { ($0.dueDate ?? .distantFuture) < start }
        let today = open.filter(isToday)
        let upcoming = open.filter { task in
            guard let due = task.dueDate else { return false }
            return due >= start && !calendar.isDateInToday(due)
        }
        let someday = open.filter { $0.dueDate == nil }
        var result: [TaskGroup] = [
            TaskGroup(id: "overdue", title: "Overdue", tint: .red, tasks: Self.ordered(overdue)),
            TaskGroup(id: "today", title: "Today", tint: Color.inkAccent, tasks: Self.ordered(today)),
            TaskGroup(id: "upcoming", title: "Upcoming", tint: .blue, tasks: Self.ordered(upcoming)),
            TaskGroup(id: "someday", title: "Someday", tint: .gray, tasks: Self.ordered(someday)),
        ]
        if showsDone {
            let done = workspace.tasks.filter { $0.status == .done }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            result.append(TaskGroup(id: "done", title: "Done", tint: .green, tasks: Array(done.prefix(50))))
        }
        return result.filter { !$0.tasks.isEmpty }
    }

    /// Hand order first, then by date.
    static func ordered(_ tasks: [PlanTask]) -> [PlanTask] {
        tasks.sorted { a, b in
            let left: Double = a.sortIndex ?? 1_000_000
            let right: Double = b.sortIndex ?? 1_000_000
            if left != right { return left < right }
            let leftDue: Date = a.dueDate ?? .distantFuture
            let rightDue: Date = b.dueDate ?? .distantFuture
            if leftDue != rightDue { return leftDue < rightDue }
            return a.createdAt < b.createdAt
        }
    }

    private var openCount: Int { workspace.tasks.filter { $0.status != .done }.count }
    private var doneToday: Int {
        workspace.tasks.filter { task in task.completedAt.map(Calendar.current.isDateInToday) ?? false }.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    header
                    addBar
                }
                .listRowBackground(Color.clear)
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            row(task, tint: group.tint)
                                .id(task.id)
                        }
                        .onMove { source, destination in
                            var ids: [UUID] = group.tasks.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            withAnimation(.snappy) { workspace.reorder(ids) }
                        }
                    } header: {
                        HStack {
                            Circle().fill(group.tint).frame(width: 8, height: 8)
                            Text(tr(group.title))
                            Text("\(group.tasks.count)").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button {
                        withAnimation(.snappy) { showsDone.toggle() }
                    } label: {
                        Label(showsDone ? "Hide Done Tasks" : "Show Done Tasks", systemImage: showsDone ? "eye.slash" : "checkmark.circle")
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .animation(.snappy, value: workspace.tasks)
            .overlay {
                if workspace.tasks.isEmpty {
                    ContentUnavailableView("Nothing to Do", systemImage: "checklist", description: Text("Type a task above and press Return."))
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: highlight) { scroll(to: highlight, proxy: proxy) }
            .onAppear { scroll(to: highlight, proxy: proxy) }
        }
    }

    private func scroll(to id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.6)) { if highlight == id { highlight = nil } }
        }
    }

    // MARK: Header and quick add

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.title2.bold())
                Text("\(openCount) open · \(doneToday) done today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let total: Int = max(openCount + doneToday, 1)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(doneToday) / CGFloat(total))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green)
            }
            .frame(width: 42, height: 42)
            .animation(.snappy, value: doneToday)
        }
        .padding(.vertical, 6)
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.inkAccent)
                TextField("Add a task", text: $newTitle)
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                Menu {
                    Picker("Priority", selection: $newPriority) {
                        ForEach(PlanTask.Priority.allCases) { Text(tr($0.title)).tag($0) }
                    }
                } label: {
                    Image(systemName: newPriority == .high ? "flag.fill" : "flag")
                        .foregroundStyle(newPriority == .high ? Color.red : newPriority == .low ? Color.gray : Color.orange)
                }
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                ForEach(QuickDue.allCases) { due in
                    Button {
                        newDue = due
                    } label: {
                        Text(tr(due.title))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(newDue == due ? Color.inkAccent.opacity(0.25) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func add() {
        guard let task = workspace.quickAdd(newTitle, due: newDue.date, priority: newPriority) else { return }
        newTitle = ""
        highlight = task.id
        addFocused = true
    }

    // MARK: Rows

    private func row(_ task: PlanTask, tint: Color) -> some View {
        let done = task.status == .done
        let isOpen = expanded.contains(task.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        workspace.setStatus(done ? .todo : .done, for: task.id)
                    }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(done ? Color.green : priorityColor(task))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: done)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: task.title.isEmpty ? tr("Untitled") : task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                    chips(task)
                    if let progress = task.stepProgress {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .tint(.green)
                            .frame(maxWidth: 220)
                    }
                }
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        if isOpen { expanded.remove(task.id) } else { expanded.insert(task.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Steps")
            }
            if isOpen { steps(task) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { edit(task) }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlight == task.id ? Color.inkAccent.opacity(0.22) : Color(uiColor: .secondarySystemGroupedBackground))
                .padding(.vertical, 2)
        )
        .swipeActions(edge: .leading) {
            Button {
                withAnimation { workspace.setStatus(done ? .todo : .done, for: task.id) }
            } label: {
                Label(done ? "Undo" : "Done", systemImage: done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation { workspace.deleteTask(task.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                var moved = task
                moved.dueDate = QuickDue.tomorrow.date
                withAnimation { workspace.save(moved) }
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            .tint(.orange)
        }
    }

    private func priorityColor(_ task: PlanTask) -> Color {
        switch task.priority {
        case .high: .red
        case .medium: .secondary
        case .low: .gray
        }
    }

    private func chips(_ task: PlanTask) -> some View {
        HStack(spacing: 8) {
            if let due = task.dueDate {
                let late: Bool = due < Date() && task.status != .done
                Label(due.formatted(.dateTime.day().month(.abbreviated).hour().minute()), systemImage: "calendar")
                    .foregroundStyle(late ? Color.red : Color.secondary)
            }
            if task.priority == .high {
                Label("High", systemImage: "flag.fill").foregroundStyle(.red)
            }
            if let progress = task.stepProgress {
                Label("\(progress.done)/\(progress.total)", systemImage: "list.bullet")
                    .foregroundStyle(.secondary)
            }
            if let noteID = task.noteID, let note = store.note(noteID) {
                Label { Text(verbatim: note.title) } icon: { Image(systemName: "book") }
                    .foregroundStyle(.teal)
                    .lineLimit(1)
            }
        }
        .font(.caption)
    }

    private func steps(_ task: PlanTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(task.subtasks ?? []) { step in
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) { workspace.toggleSubtask(step.id, in: task.id) }
                    } label: {
                        Image(systemName: step.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(step.isDone ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(verbatim: step.title)
                        .strikethrough(step.isDone)
                        .foregroundStyle(step.isDone ? Color.secondary : Color.primary)
                    Spacer()
                    Button {
                        withAnimation(.snappy) { workspace.deleteSubtask(step.id, in: task.id) }
                    } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("Add a step", text: Binding(
                    get: { stepDrafts[task.id] ?? "" },
                    set: { stepDrafts[task.id] = $0 }
                ))
                .onSubmit {
                    workspace.addSubtask(stepDrafts[task.id] ?? "", to: task.id)
                    stepDrafts[task.id] = ""
                }
            }
            .font(.subheadline)
        }
        .padding(.leading, 40)
    }
}

/// The sidebar's To-Do: today's open tasks with checkboxes and a quick add.
struct SidebarToDo: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Binding var scope: LibraryScope?
    @State private var draft = ""

    private var shown: [PlanTask] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let open = workspace.tasks.filter { task in
            guard task.status != .done else { return false }
            guard let due = task.dueDate else { return true }
            return due < end
        }
        return Array(ToDoListView.ordered(open).prefix(7))
    }

    var body: some View {
        Section {
            ForEach(shown) { task in
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            workspace.setStatus(.done, for: task.id)
                        }
                    } label: {
                        Image(systemName: "circle")
                            .foregroundStyle(task.priority == .high ? Color.red : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(verbatim: task.title.isEmpty ? tr("Untitled") : task.title)
                        .lineLimit(1)
                    Spacer()
                    if let due = task.dueDate, due < Calendar.current.startOfDay(for: Date()) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(Color.inkAccent)
                TextField("Add a task for today", text: $draft)
                    .onSubmit {
                        workspace.quickAdd(draft, due: ToDoListView.QuickDue.today.date)
                        draft = ""
                    }
            }
            Button {
                UserDefaults.standard.set(PlannerView.Mode.todo.rawValue, forKey: "plannerMode")
                scope = .planner
            } label: {
                Label("All Tasks", systemImage: "checklist")
            }
        } header: {
            Text("To-Do")
        }
    }
}
