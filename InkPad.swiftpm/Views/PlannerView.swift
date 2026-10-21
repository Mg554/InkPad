import SwiftUI

/// Notion-style task planner: a board by status, a list by due date, and a calendar.
struct PlannerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case board = "Board"
        case list = "List"
        case calendar = "Calendar"
        var id: Self { self }
    }

    @EnvironmentObject private var workspace: WorkspaceStore
    @AppStorage("plannerMode") private var mode: Mode = .board
    @State private var editing: PlanTask?
    @State private var selectedDay = Date()
    @State private var targetedColumn: PlanTask.Status?

    var body: some View {
        Group {
            switch mode {
            case .board: board
            case .list: list
            case .calendar: calendar
            }
        }
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = PlanTask(dueDate: mode == .calendar ? selectedDay : nil)
                } label: {
                    Label("New Task", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task)
        }
    }

    // MARK: Board

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(PlanTask.Status.allCases) { status in
                    boardColumn(status)
                }
            }
            .padding(20)
        }
    }

    private func boardColumn(_ status: PlanTask.Status) -> some View {
        let tasks = workspace.tasks.filter { $0.status == status }.sorted(by: Self.byDueDate)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(status.title, systemImage: status.systemImage)
                    .font(.headline)
                Text("\(tasks.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editing = PlanTask(status: status)
                } label: {
                    Image(systemName: "plus")
                }
            }
            ForEach(tasks) { task in
                Button {
                    editing = task
                } label: {
                    TaskCard(task: task)
                }
                .buttonStyle(PressableStyle())
                .draggable(task.id.uuidString) {
                    TaskCard(task: task).frame(width: 260)
                }
                .contextMenu { taskMenu(task) }
                .transition(.scale.combined(with: .opacity))
            }
            if tasks.isEmpty {
                Text("Drop tasks here")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300)
        .frame(minHeight: 400, alignment: .top)
        .glowCard(Self.color(for: status), isActive: targetedColumn == status)
        .scaleEffect(targetedColumn == status ? 1.02 : 1)
        .animation(.snappy, value: targetedColumn)
        .animation(.snappy, value: tasks.map(\.id))
        // Drag a card onto another column to change its status.
        .dropDestination(for: String.self) { ids, _ in
            withAnimation(.snappy) {
                for id in ids.compactMap(UUID.init(uuidString:)) {
                    workspace.setStatus(status, for: id)
                }
            }
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                targetedColumn = status
            } else if targetedColumn == status {
                targetedColumn = nil
            }
        }
    }

    // MARK: List

    private var list: some View {
        let open = workspace.tasks.filter { $0.status != .done }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let sections: [(String, [PlanTask])] = [
            ("Overdue", open.filter { ($0.dueDate ?? .distantFuture) < startOfToday }),
            ("Today", open.filter { $0.dueDate.map(calendar.isDateInToday) ?? false }),
            ("Upcoming", open.filter { ($0.dueDate ?? .distantPast) >= startOfToday && !($0.dueDate.map(calendar.isDateInToday) ?? false) }),
            ("No Date", open.filter { $0.dueDate == nil }),
            ("Done", workspace.tasks.filter { $0.status == .done }),
        ]
        return List {
            ForEach(sections, id: \.0) { section in
                if !section.1.isEmpty {
                    Section(section.0) {
                        ForEach(section.1.sorted(by: Self.byDueDate)) { task in
                            taskRow(task)
                        }
                    }
                }
            }
        }
        .overlay {
            if workspace.tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("Tap + to plan your first task."))
            }
        }
    }

    private func taskRow(_ task: PlanTask) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    workspace.setStatus(task.status == .done ? .todo : .done, for: task.id)
                }
            } label: {
                Image(systemName: task.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(task.status == .done ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: task.status)
                    .shadow(color: task.status == .done ? .green.opacity(0.6) : .clear, radius: 6)
            }
            .buttonStyle(PressableStyle())
            TaskSummary(task: task)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = task }
        .swipeActions {
            Button(role: .destructive) {
                workspace.deleteTask(task.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu { taskMenu(task) }
    }

    // MARK: Calendar

    private var calendar: some View {
        let dayTasks = workspace.tasks.filter { task in
            task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: selectedDay) } ?? false
        }
        return HStack(alignment: .top, spacing: 0) {
            DatePicker("Day", selection: $selectedDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .frame(width: 360)
                .padding()
            Divider()
            List {
                Section(selectedDay.formatted(date: .complete, time: .omitted)) {
                    if dayTasks.isEmpty {
                        Text("Nothing planned").foregroundStyle(.secondary)
                    }
                    ForEach(dayTasks.sorted(by: Self.byDueDate)) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    // MARK: Shared

    @ViewBuilder
    private func taskMenu(_ task: PlanTask) -> some View {
        ForEach(PlanTask.Status.allCases) { status in
            Button {
                workspace.setStatus(status, for: task.id)
            } label: {
                Label(status.title, systemImage: status.systemImage)
            }
            .disabled(task.status == status)
        }
        Divider()
        Button(role: .destructive) {
            workspace.deleteTask(task.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    static func color(for status: PlanTask.Status) -> Color {
        switch status {
        case .todo: return .blue
        case .inProgress: return .orange
        case .done: return .green
        }
    }

    private static func byDueDate(_ a: PlanTask, _ b: PlanTask) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): x < y
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a.createdAt < b.createdAt
        }
    }
}

private struct TaskCard: View {
    let task: PlanTask

    var body: some View {
        TaskSummary(task: task)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // High-priority and in-progress tasks glow.
            .glowCard(
                task.priority == .high ? .red : PlannerView.color(for: task.status),
                isActive: task.priority == .high || task.status == .inProgress
            )
            .foregroundStyle(.primary)
    }
}

private struct TaskSummary: View {
    let task: PlanTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.body.weight(.medium))
                .strikethrough(task.status == .done)
            HStack(spacing: 8) {
                PriorityBadge(priority: task.priority)
                if let due = task.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) && task.status != .done ? Color.red : Color.secondary)
                }
                ForEach(task.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}

private struct PriorityBadge: View {
    let priority: PlanTask.Priority

    private var color: Color {
        switch priority {
        case .low: return .gray
        case .medium: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        Text(priority.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Create or edit a task, like a Notion page's properties.
private struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var task: PlanTask
    @State private var hasDueDate: Bool
    @State private var tagsText: String

    init(task: PlanTask) {
        _task = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task name", text: $task.title)
                        .font(.title3)
                }
                Section("Properties") {
                    Picker("Status", selection: $task.status) {
                        ForEach(PlanTask.Status.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    Picker("Priority", selection: $task.priority) {
                        ForEach(PlanTask.Priority.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: Binding(
                            get: { task.dueDate ?? Date() },
                            set: { task.dueDate = $0 }
                        ))
                    }
                    TextField("Tags (comma separated)", text: $tagsText)
                }
                Section("Notes") {
                    TextField("Details", text: $task.notes, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle(workspace.tasks.contains { $0.id == task.id } ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = task
                        saved.dueDate = hasDueDate ? (task.dueDate ?? Date()) : nil
                        saved.tags = tagsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        workspace.save(saved)
                        dismiss()
                    }
                }
            }
        }
    }
}
