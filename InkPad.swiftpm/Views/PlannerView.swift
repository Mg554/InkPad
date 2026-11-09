import SwiftUI

/// Notion-style task planner: a board by status, a list by due date, and a calendar.
struct PlannerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case today = "Today"
        case board = "Board"
        case list = "List"
        case calendar = "Calendar"
        case matrix = "Matrix"
        case timeline = "Timeline"
        case review = "Review"
        var id: Self { self }
    }

    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: LibraryStore
    @AppStorage("plannerMode") private var mode: Mode = .board
    @State private var editing: PlanTask?
    @State private var selectedDay = Date()
    @State private var targetedColumn: PlanTask.Status?
    @ObservedObject private var looks = FlowLookStore.shared
    @State private var isCustomizing = false

    var body: some View {
        Group {
            switch mode {
            case .today: PlannerTodayView { editing = $0 }
            case .board: board
            case .list: list
            case .calendar: calendar
            case .matrix: PlannerMatrixView { editing = $0 }
            case .timeline: PlannerTimelineView { editing = $0 }
            case .review: PlannerWeeklyReview()
            }
        }
        .screenBackdrop(looks.look.backdrop)
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 600)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCustomizing = true
                } label: {
                    Label("Customize", systemImage: "paintbrush")
                }
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
        .sheet(isPresented: $isCustomizing) {
            FlowStyleView()
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
                    TaskCard(task: task).frame(width: 260).environmentObject(store)
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
        if task.status != .done {
            Button {
                FocusLauncher.focus(on: task, workspace: workspace)
            } label: {
                Label("Focus on This", systemImage: "play.circle")
            }
            Divider()
        }
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
    @ObservedObject private var looks = FlowLookStore.shared

    var body: some View {
        // High-priority and in-progress tasks glow, in the chosen card style.
        let tint: Color = task.priority == .high ? .red : PlannerView.color(for: task.status)
        let isActive: Bool = task.priority == .high || task.status == .inProgress
        TaskSummary(task: task)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .flowCard(looks.look, tint: tint, isActive: isActive)
    }
}

private struct TaskSummary: View {
    @EnvironmentObject private var store: LibraryStore
    let task: PlanTask

    private func studyLabel(_ title: String) -> String {
        if let chapter = task.chapterTitle { return "\(title) · \(chapter)" }
        return title
    }

    /// Focus time logged, and the estimate: "25 / 30 min".
    private var timeText: String {
        let done = (task.focusSeconds ?? 0) / 60
        guard let estimate = task.estimateMinutes else { return "\(done) min" }
        return "\(done) / \(estimate) min"
    }

    private var isOverEstimate: Bool {
        guard let estimate = task.estimateMinutes else { return false }
        return (task.focusSeconds ?? 0) > estimate * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.body.weight(.medium))
                .strikethrough(task.status == .done)
            // Chips wrap as whole chips to the next line.
            ChipFlow(spacing: 8) {
                PriorityBadge(priority: task.priority)
                if let due = task.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) && task.status != .done ? Color.red : Color.secondary)
                }
                if let noteID = task.noteID, let note = store.note(noteID) {
                    Label(studyLabel(note.title), systemImage: "book")
                        .font(.caption)
                        .foregroundStyle(.teal)
                        .lineLimit(1)
                }
                if let step = task.reviewStep, step > 0 {
                    Label("Review \(step)/3", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
                if task.estimateMinutes != nil || (task.focusSeconds ?? 0) > 0 {
                    Label(timeText, systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(isOverEstimate ? Color.orange : Color.secondary)
                }
                ForEach(task.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.inkAccent.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}

/// Lays chips out in rows, each kept whole on one line.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height: CGFloat = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width: CGFloat = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let fitted = CGSize(width: min(size.width, bounds.width), height: size.height)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(fitted))
                x += fitted.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth: CGFloat = min(size.width, width)
            let last = rows.count - 1
            let needed: CGFloat = rows[last].indices.isEmpty ? itemWidth : rows[last].width + spacing + itemWidth
            if needed > width, !rows[last].indices.isEmpty {
                rows.append(Row(indices: [index], width: itemWidth, height: size.height))
            } else {
                rows[last].indices.append(index)
                rows[last].width = needed
                rows[last].height = max(rows[last].height, size.height)
            }
        }
        return rows
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
    @EnvironmentObject private var store: LibraryStore
    @State private var task: PlanTask
    @State private var hasDueDate: Bool
    @State private var tagsText: String

    private var studySection: some View {
        Section {
            Picker("Note or Book", selection: $task.noteID) {
                Text("None").tag(UUID?.none)
                ForEach(store.notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { note in
                    Text(note.title).tag(Optional(note.id))
                }
            }
            .pickerStyle(.navigationLink)
            if let noteID = task.noteID {
                TextField("Chapter or pages (optional)", text: Binding(
                    get: { task.chapterTitle ?? "" },
                    set: { task.chapterTitle = $0.isEmpty ? nil : $0 }
                ))
                Toggle("Review It After 1, 3 and 7 Days", isOn: Binding(
                    get: { task.schedulesReviews ?? false },
                    set: { task.schedulesReviews = $0 }
                ))
                Button {
                    workspace.save(savedTask())
                    dismiss()
                    CommandCenter.shared.openNote(noteID)
                } label: {
                    Label("Open the Note", systemImage: "book")
                }
            }
        } header: {
            Text("Study")
        } footer: {
            Text("Link a task to what you study. With reviews on, finishing it plans a review the next day, then 3 and 7 days later.")
        }
    }

    /// The task with the due date and tags as edited.
    private func savedTask() -> PlanTask {
        var saved = task
        saved.dueDate = hasDueDate ? (task.dueDate ?? Date()) : nil
        // Reviews belong to a linked note.
        if saved.noteID == nil { saved.schedulesReviews = nil }
        saved.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return saved
    }

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
                Section {
                    Stepper(value: Binding(
                        get: { task.estimateMinutes ?? 0 },
                        set: { task.estimateMinutes = $0 > 0 ? $0 : nil }
                    ), in: 0...600, step: 5) {
                        Text(task.estimateMinutes.map { "Estimate: \($0) min" } ?? "No estimate")
                    }
                    if let estimate = task.estimateMinutes, let factor = PlannerInsights.estimateFactor(workspace.tasks) {
                        let suggested = PlannerInsights.suggestedMinutes(estimate, factor: factor)
                        if suggested != estimate {
                            Button("Your history suggests \(suggested) min — use it") { task.estimateMinutes = suggested }
                                .font(.callout)
                        }
                    }
                    if let seconds = task.focusSeconds, seconds > 0 {
                        LabeledContent("Focused so far", value: PlannerInsights.duration(seconds))
                    }
                    if task.status != .done, workspace.tasks.contains(where: { $0.id == task.id }) {
                        Button {
                            let saved = savedTask()
                            workspace.save(saved)
                            FocusLauncher.focus(on: saved, workspace: workspace)
                            dismiss()
                        } label: {
                            Label("Focus on This", systemImage: "play.circle.fill")
                        }
                    }
                } header: {
                    Text("Time")
                } footer: {
                    Text("Focus on This starts Flowmodoro and logs the time here. InkPad learns how long your tasks really take.")
                }
                studySection
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
                        workspace.save(savedTask())
                        dismiss()
                    }
                }
            }
        }
    }
}
