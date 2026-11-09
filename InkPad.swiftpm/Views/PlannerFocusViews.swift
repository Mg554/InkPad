import EventKit
import SwiftUI

/// Starts Flowmodoro on a planner task and opens the timer.
@MainActor
enum FocusLauncher {
    static func focus(on task: PlanTask, workspace: WorkspaceStore) {
        if workspace.flowTimer?.phase == .working {
            CommandCenter.shared.say("A focus session is already running")
        } else if workspace.flowTimer != nil {
            CommandCenter.shared.say("Take or skip your break first")
        } else {
            workspace.startFocus(onPlanTask: task.id)
            CommandCenter.shared.say("Focusing on “\(task.title.isEmpty ? "Untitled" : task.title)”")
        }
        CommandCenter.shared.navigate(.flowmodoro)
    }
}

// MARK: Today

/// Today: an hour timeline with planned tasks, focus done, and reminders due.
struct PlannerTodayView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var reminders = ReminderCenter.shared
    let edit: (PlanTask) -> Void

    private static let firstHour = 6
    private static let lastHour = 23
    private static let hourHeight: CGFloat = 64

    private var todayTasks: [PlanTask] {
        PlannerInsights.todayCandidates(workspace.tasks)
    }

    private var scheduled: [PlanTask] {
        workspace.tasks.filter { task in
            guard task.status != .done, let start = task.scheduledAt else { return false }
            return Calendar.current.isDateInToday(start)
        }
    }

    private var unscheduled: [PlanTask] {
        let planned = Set(scheduled.map(\.id))
        return todayTasks.filter { !planned.contains($0.id) }
    }

    /// Open tasks not planned for today.
    private var otherOpen: [PlanTask] {
        let today = Set(todayTasks.map(\.id))
        return workspace.tasks.filter { $0.status != .done && !today.contains($0.id) }
    }

    private var todaySessions: [FlowSession] {
        workspace.flowSessions.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    timeline
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .onAppear {
                    let hour = max(Calendar.current.component(.hour, from: Date()) - 1, Self.firstHour)
                    proxy.scrollTo(hour, anchor: .top)
                }
            }
            Divider()
            sidePanel
                .frame(width: 340)
        }
        .task { await reminders.refresh() }
    }

    // MARK: Timeline

    private var timeline: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Self.firstHour...Self.lastHour, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 8) {
                        Text(PlannerInsights.hourLabel(hour))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                        VStack { Divider() }
                    }
                    .frame(height: Self.hourHeight, alignment: .top)
                    .id(hour)
                }
            }
            GeometryReader { geometry in
                let width = geometry.size.width - 70
                ForEach(todaySessions) { session in
                    sessionBlock(session, width: width)
                }
                ForEach(scheduled) { task in
                    taskBlock(task, width: width)
                }
                nowLine(width: width)
            }
        }
        .frame(height: CGFloat(Self.lastHour - Self.firstHour + 1) * Self.hourHeight)
    }

    private func offset(of date: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let raw: Double = Double(hour - Self.firstHour) + Double(minute) / 60
        let lastHours: Double = Double(Self.lastHour - Self.firstHour + 1)
        let hours: Double = min(max(raw, 0), lastHours)
        return CGFloat(hours) * Self.hourHeight
    }

    private func taskBlock(_ task: PlanTask, width: CGFloat) -> some View {
        let factor = PlannerInsights.estimateFactor(workspace.tasks)
        let minutes = PlannerInsights.plannedMinutes(task, factor: factor)
        let height = max(CGFloat(minutes) / 60 * Self.hourHeight, 24)
        let tint: Color = task.important ? .red : .blue
        let title = task.title.isEmpty ? "Untitled" : task.title
        return HStack(spacing: 8) {
            if height < 48 {
                // Short blocks: title and length on one line.
                Text("\(title) · \(minutes) min").font(.caption.weight(.semibold)).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(2)
                    Text("\(minutes) min").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                FocusLauncher.focus(on: task, workspace: workspace)
            } label: {
                Image(systemName: "play.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .frame(width: width * 0.62, height: height, alignment: .leading)
        .clipped()
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4) }
        .contentShape(Rectangle())
        .onTapGesture { edit(task) }
        .offset(x: 70, y: offset(of: task.scheduledAt ?? Date()))
    }

    private func sessionBlock(_ session: FlowSession, width: CGFloat) -> some View {
        let height = max(CGFloat(session.workSeconds) / 3600 * Self.hourHeight, 6)
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.green.opacity(0.35))
            .overlay(alignment: .topLeading) {
                if height > 18 {
                    Text(session.taskTitle).font(.caption2).lineLimit(1).padding(.horizontal, 6).padding(.top, 2)
                }
            }
            .frame(width: width * 0.34, height: height)
            .offset(x: 70 + width * 0.64, y: offset(of: session.startedAt))
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .frame(width: width + 8)
            .offset(x: 62, y: offset(of: context.date) - 4)
        }
    }

    // MARK: Side

    private var sidePanel: some View {
        List {
            Section {
                focusSummary
                Button {
                    planMyDay()
                } label: {
                    Label("Plan My Day", systemImage: "wand.and.stars")
                }
                .disabled(todayTasks.isEmpty)
            } footer: {
                Text(planFooter)
            }
            Section("To Plan Today") {
                if unscheduled.isEmpty {
                    Text("Everything for today has a time.").foregroundStyle(.secondary)
                }
                ForEach(unscheduled) { task in
                    HStack {
                        Text(task.title.isEmpty ? "Untitled" : task.title).lineLimit(2)
                        Spacer()
                        Button {
                            FocusLauncher.focus(on: task, workspace: workspace)
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { edit(task) }
                }
            }
            if !otherOpen.isEmpty {
                Section {
                    ForEach(otherOpen) { task in
                        HStack {
                            Text(task.title.isEmpty ? "Untitled" : task.title).lineLimit(2).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                var planned = task
                                planned.scheduledAt = Date()
                                withAnimation(.snappy) { workspace.save(planned) }
                            } label: {
                                Label("Today", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("Other Open Tasks")
                } footer: {
                    Text("Add a task to today, then Plan My Day gives it a time.")
                }
            }
            if reminders.access == .granted {
                Section("Reminders Due Today") {
                    let due = reminders.reminders(in: .today)
                    if due.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(due, id: \.calendarItemIdentifier) { reminder in
                        Label(reminder.title ?? "Reminder", systemImage: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var focusSummary: some View {
        let seconds = todaySessions.reduce(0) { $0 + $1.workSeconds }
        return HStack {
            VStack(alignment: .leading) {
                Text(PlannerInsights.duration(seconds)).font(.title2.bold()).foregroundStyle(.green)
                Text("focused today").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(todaySessions.count)").font(.title2.bold())
                Text("sessions").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var planFooter: String {
        let best = PlannerInsights.bestHours(PlannerInsights.focusByHour(workspace.flowSessions))
        guard !best.isEmpty else {
            return "Puts today's tasks into time blocks with breaks. After a few Flowmodoro sessions, hard tasks go into your best focus hours."
        }
        let labels = best.map(PlannerInsights.hourLabel).joined(separator: ", ")
        return "Hard tasks go into your best focus hours (\(labels)), with breaks between."
    }

    private func planMyDay() {
        let plan = PlannerInsights.planDay(tasks: workspace.tasks, sessions: workspace.flowSessions, breakShare: max(workspace.flowBreakShare, 10))
        guard !plan.isEmpty else {
            CommandCenter.shared.say("No time left today to plan")
            return
        }
        let candidates = Set(PlannerInsights.todayCandidates(workspace.tasks).map(\.id))
        withAnimation(.snappy) { workspace.schedule(plan, replacing: candidates) }
        CommandCenter.shared.say("Planned \(plan.count) tasks")
    }
}

// MARK: Eisenhower

/// Important × urgent: drag tasks between the four boxes.
struct PlannerMatrixView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let edit: (PlanTask) -> Void

    private struct Quadrant: Identifiable {
        let id: Int
        let title: String
        let hint: String
        let important: Bool
        let urgent: Bool
        let color: Color
    }

    private let quadrants: [Quadrant] = [
        Quadrant(id: 0, title: "Do Now", hint: "Important and urgent", important: true, urgent: true, color: .red),
        Quadrant(id: 1, title: "Schedule", hint: "Important, not urgent", important: true, urgent: false, color: .blue),
        Quadrant(id: 2, title: "Delegate or Batch", hint: "Urgent, not important", important: false, urgent: true, color: .orange),
        Quadrant(id: 3, title: "Later or Drop", hint: "Neither", important: false, urgent: false, color: .gray),
    ]

    var body: some View {
        GeometryReader { geometry in
            let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(quadrants) { quadrant in
                    box(quadrant)
                        .frame(height: max((geometry.size.height - 54) / 2, 220))
                }
            }
            .padding(20)
        }
    }

    private func box(_ quadrant: Quadrant) -> some View {
        let tasks = workspace.tasks.filter { $0.status != .done && $0.important == quadrant.important && $0.urgent == quadrant.urgent }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(quadrant.title).font(.headline).foregroundStyle(quadrant.color)
                Text("\(tasks.count)").foregroundStyle(.secondary)
                Spacer()
                Text(quadrant.hint).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(tasks) { task in
                        HStack {
                            Text(task.title.isEmpty ? "Untitled" : task.title).lineLimit(2)
                            Spacer()
                            Button {
                                FocusLauncher.focus(on: task, workspace: workspace)
                            } label: {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                        .onTapGesture { edit(task) }
                        .draggable(task.id.uuidString)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(quadrant.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(quadrant.color.opacity(0.35)))
        .dropDestination(for: String.self) { ids, _ in
            withAnimation(.snappy) {
                for id in ids.compactMap(UUID.init(uuidString:)) {
                    workspace.setMatrix(important: quadrant.important, urgent: quadrant.urgent, for: id)
                }
            }
            return true
        }
    }
}

// MARK: Weekly Review

/// The last seven days: focus per day, tasks done, distractions, what to keep.
struct PlannerWeeklyReview: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        let week = PlannerInsights.week(tasks: workspace.tasks, sessions: workspace.flowSessions, distractions: workspace.distractions)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    stat(PlannerInsights.duration(week.totalFocus), "focused", .green)
                    stat("\(week.sessions)", "sessions", .blue)
                    stat("\(week.tasksDone)", "tasks done", .purple)
                    stat("\(week.distractions)", "distractions caught", .orange)
                }
                chart(week)
                insights(week)
                if !week.topTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where the Time Went").font(.headline)
                        ForEach(week.topTasks, id: \.title) { item in
                            HStack {
                                Text(item.title).lineLimit(1)
                                Spacer()
                                Text(PlannerInsights.duration(item.seconds)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    .padding(16)
                    .themedCard()
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .themedCard()
    }

    private func chart(_ week: PlannerInsights.Week) -> some View {
        let most = max(week.focusPerDay.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Focus per Day").font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    let seconds = week.focusPerDay[index]
                    let share: CGFloat = CGFloat(seconds) / CGFloat(most)
                    VStack(spacing: 6) {
                        Text(seconds > 0 ? PlannerInsights.duration(seconds) : "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.gradient)
                            .frame(height: max(share * 160, 4))
                        Text(week.dayStarts[index].formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 210, alignment: .bottom)
        }
        .padding(16)
        .themedCard()
    }

    private func insights(_ week: PlannerInsights.Week) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the Week Says").font(.headline)
            if let hour = week.bestHour {
                Label("Your best focus starts around \(PlannerInsights.hourLabel(hour)). Plan hard tasks there.", systemImage: "sun.max")
            }
            if let factor = week.estimateFactor {
                let percent = Int(((factor - 1) * 100).rounded())
                if percent > 5 {
                    Label("Tasks take about \(percent)% longer than you estimate. New estimates are corrected for that.", systemImage: "hourglass")
                } else if percent < -5 {
                    Label("Tasks take about \(-percent)% less than you estimate.", systemImage: "hourglass")
                } else {
                    Label("Your estimates are right on.", systemImage: "checkmark.seal")
                }
            } else {
                Label("Give tasks an estimate and use Focus on This to learn how long things really take.", systemImage: "hourglass")
            }
            if week.distractions > 0 {
                let noun = week.distractions == 1 ? "distraction" : "distractions"
                Label("\(week.distractions) \(noun) caught. Review them in the Distraction Box.", systemImage: "tray")
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themedCard()
    }
}

// MARK: Timeline (Gantt)

/// Tasks as bars over the coming weeks: from when they start (planned, or
/// created) to when they are due.
struct PlannerTimelineView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let edit: (PlanTask) -> Void

    private static let dayWidth: CGFloat = 46
    private static let rowHeight: CGFloat = 40
    private static let titleWidth: CGFloat = 220
    private static let days = 28

    private var firstDay: Date {
        Calendar.current.date(byAdding: .day, value: -3, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var rows: [PlanTask] {
        let first = firstDay
        return workspace.tasks
            .filter { task in
                let end = span(of: task).end
                return task.status != .done || end >= first
            }
            .sorted { span(of: $0).start < span(of: $1).start }
    }

    private func span(of task: PlanTask) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: task.scheduledAt ?? task.createdAt)
        let due = calendar.startOfDay(for: task.dueDate ?? task.scheduledAt ?? task.createdAt)
        return (min(start, due), max(start, due))
    }

    private func dayIndex(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: firstDay, to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 44)
                    ForEach(rows) { task in
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.callout)
                            .lineLimit(1)
                            .strikethrough(task.status == .done)
                            .frame(width: Self.titleWidth - 16, height: Self.rowHeight, alignment: .leading)
                            .padding(.leading, 16)
                            .contentShape(Rectangle())
                            .onTapGesture { edit(task) }
                    }
                }
                .frame(width: Self.titleWidth)
                Divider()
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        dayHeader
                        ZStack(alignment: .topLeading) {
                            grid
                            ForEach(Array(rows.enumerated()), id: \.element.id) { item in
                                bar(item.element, row: item.offset)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .overlay {
            if workspace.tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "chart.bar.xaxis", description: Text("Tasks with dates show as bars here."))
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<Self.days, id: \.self) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.caption.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .frame(width: 24, height: 24)
                        .background(isToday ? Color.red : Color.clear, in: Circle())
                }
                .frame(width: Self.dayWidth, height: 44)
            }
        }
    }

    private var grid: some View {
        let height = max(CGFloat(rows.count) * Self.rowHeight, 200)
        return HStack(spacing: 0) {
            ForEach(0..<Self.days, id: \.self) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
                let weekend = Calendar.current.isDateInWeekend(day)
                Rectangle()
                    .fill(weekend ? Color.secondary.opacity(0.07) : Color.clear)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.12)).frame(width: 0.5) }
                    .overlay {
                        if Calendar.current.isDateInToday(day) {
                            Rectangle().fill(Color.red.opacity(0.08))
                        }
                    }
                    .frame(width: Self.dayWidth, height: height)
            }
        }
    }

    private func bar(_ task: PlanTask, row: Int) -> some View {
        let range = span(of: task)
        // Older open tasks start at the first day, marked overdue.
        let startIndex = min(max(dayIndex(range.start), 0), Self.days - 1)
        let endIndex = max(min(dayIndex(range.end), Self.days - 1), startIndex)
        let length = max(endIndex - startIndex + 1, 1)
        let tint: Color = task.status == .done ? .green : (task.important ? .red : PlannerView.color(for: task.status))
        let overdue: Bool = task.status != .done && (task.dueDate ?? .distantFuture) < Calendar.current.startOfDay(for: Date())
        return RoundedRectangle(cornerRadius: 8)
            .fill(tint.opacity(task.status == .done ? 0.35 : 0.75).gradient)
            .overlay(alignment: .leading) {
                if let estimate = task.estimateMinutes {
                    Text("\(estimate)m").font(.caption2.weight(.semibold)).foregroundStyle(.white).padding(.leading, 6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(overdue ? Color.red : Color.clear, lineWidth: 2))
            .frame(width: CGFloat(length) * Self.dayWidth - 6, height: Self.rowHeight - 12)
            .offset(x: CGFloat(startIndex) * Self.dayWidth + 3, y: CGFloat(row) * Self.rowHeight + 6)

            .onTapGesture { edit(task) }
    }
}
