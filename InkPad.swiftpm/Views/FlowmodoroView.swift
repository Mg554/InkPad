import AudioToolbox
import SwiftUI

/// Flowmodoro, from the Pythonation/flowmodoro-wep-app web app: pick a task
/// and the work stopwatch starts; stop when your focus fades and you earn a
/// break that is a share of the time you worked. Tasks can be added, edited,
/// ticked off, reordered (drag) and deleted, and every session is kept in
/// the history.
struct FlowmodoroView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var newTask = ""
    @State private var prompt: NamePrompt?
    @State private var isConfirmingClear = false

    private var timer: FlowTimer? { workspace.flowTimer }
    private var isWorking: Bool { timer?.phase == .working }

    var body: some View {
        List {
            Section {
                timerCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section {
                HStack {
                    TextField("Add a new task…", text: $newTask)
                        .onSubmit(addTask)
                    Button("Add", action: addTask)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if workspace.flowTasks.isEmpty {
                    Text("No tasks yet. Add one to start.")
                        .foregroundStyle(.secondary)
                }
                ForEach(workspace.flowTasks) { task in
                    taskRow(task)
                }
                .onMove { workspace.moveFlowTasks(from: $0, to: $1) }
            } header: {
                Text("Tasks")
            } footer: {
                Text("Tap a task to start working on it. Hold and drag to reorder.")
            }

            Section {
                if workspace.flowSessions.isEmpty {
                    Text("No sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    todaySummary
                    ForEach(Array(workspace.flowSessions.reversed())) { session in
                        sessionRow(session)
                    }
                }
            } header: {
                HStack {
                    Text("History")
                    Spacer()
                    if !workspace.flowSessions.isEmpty {
                        Button("Clear") { isConfirmingClear = true }
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Flowmodoro")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Break Length", selection: Binding(
                        get: { workspace.flowBreakShare },
                        set: { workspace.setFlowBreakShare($0) }
                    )) {
                        ForEach(Flowmodoro.breakShares, id: \.self) { share in
                            Text(share == 20 ? "\(share)% of work time (classic)" : "\(share)% of work time").tag(share)
                        }
                    }
                } label: {
                    Label("Break Length", systemImage: "cup.and.saucer")
                }
                AppearanceMenu()
            }
        }
        .namePrompt($prompt)
        .confirmationDialog("Clear the session history?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { workspace.clearFlowHistory() }
        }
        .task(id: timer?.breakEndsAt) {
            await waitForBreakEnd()
        }
    }

    // MARK: Timer

    private var timerCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 16) {
                Text("Work with focus, rest wisely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                currentTask
                HStack(spacing: 14) {
                    timerBox(
                        "Work Time",
                        value: Flowmodoro.clock(timer?.workElapsed(at: context.date) ?? 0, forceHours: true),
                        tint: .green,
                        isRunning: timer?.phase == .working
                    )
                    timerBox(
                        "Break Time",
                        value: Flowmodoro.clock(timer?.breakRemaining(at: context.date) ?? 0),
                        tint: .blue,
                        isRunning: timer?.phase == .onBreak
                    )
                }
                controls
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var currentTask: some View {
        if let timer {
            VStack(spacing: 4) {
                Text(timer.phase == .working ? "Focusing on" : "Last session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(timer.taskTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("Pick a task to start")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func timerBox(_ title: String, value: String, tint: Color, isRunning: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .glowCard(tint, isActive: isRunning)
    }

    @ViewBuilder
    private var controls: some View {
        switch timer?.phase {
        case .working?:
            HStack {
                Button(role: .destructive) {
                    workspace.stopFlowWork()
                } label: {
                    Label("Stop Work Session", systemImage: "stop.fill")
                        .frame(minWidth: 200, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                Menu {
                    Button("Discard This Session", role: .destructive) { workspace.discardFlowWork() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
                .accessibilityLabel("More")
            }
        case .breakReady?:
            HStack {
                Button {
                    startBreak()
                } label: {
                    Label("Start Break", systemImage: "cup.and.saucer.fill")
                        .frame(minWidth: 160, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                Button("Skip Break") { workspace.endFlowBreak() }
                    .buttonStyle(.bordered)
            }
        case .onBreak?:
            Button("End Break Now") { endBreak(playSound: false) }
                .buttonStyle(.bordered)
        case nil:
            EmptyView()
        }
    }

    // MARK: Tasks

    private func taskRow(_ task: FlowTask) -> some View {
        let isActive = timer?.taskID == task.id && isWorking
        return HStack(spacing: 12) {
            Button {
                workspace.toggleFlowTask(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isActive)
            .accessibilityLabel(task.isDone ? "Reopen Task" : "Complete Task")

            Button {
                workspace.startFlowWork(on: task.id)
            } label: {
                HStack {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if isActive {
                        Image(systemName: "timer")
                            .foregroundStyle(.green)
                            .symbolEffect(.pulse)
                    } else if !task.isDone && !isWorking {
                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.isDone || isWorking)
        }
        .listRowBackground(isActive ? Color.green.opacity(0.12) : nil)
        .swipeActions {
            if !isActive {
                Button(role: .destructive) {
                    workspace.deleteFlowTask(task.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if !task.isDone {
                Button {
                    rename(task)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if !task.isDone {
                Button {
                    rename(task)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button {
                workspace.toggleFlowTask(task.id)
            } label: {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            .disabled(isActive)
            Button(role: .destructive) {
                workspace.deleteFlowTask(task.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isActive)
        }
    }

    private func addTask() {
        workspace.addFlowTask(newTask)
        newTask = ""
    }

    private func rename(_ task: FlowTask) {
        prompt = NamePrompt(title: "Edit Task", initialText: task.title, confirmTitle: "Save") { title in
            workspace.renameFlowTask(task.id, to: title)
        }
    }

    // MARK: History

    private var todaySummary: some View {
        let today = workspace.flowSessions.filter { Calendar.current.isDateInToday($0.endedAt) }
        let worked = today.reduce(0) { $0 + $1.workSeconds }
        return Label {
            Text("Today: \(Flowmodoro.duration(worked)) of focus in \(today.count) \(today.count == 1 ? "session" : "sessions")")
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
        }
    }

    private func sessionRow(_ session: FlowSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.taskTitle)
                .font(.body.weight(.semibold))
            Text("Work \(Flowmodoro.clock(session.workSeconds, forceHours: true)) · Break \(Flowmodoro.clock(session.breakSeconds))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Break

    private func startBreak() {
        workspace.startFlowBreak()
    }

    private func endBreak(playSound: Bool) {
        workspace.endFlowBreak()
        if playSound {
            FlowAlert.playSound()
        }
    }

    /// Waits until the break runs out, then ends it with a sound.
    private func waitForBreakEnd() async {
        guard timer?.phase == .onBreak, let end = timer?.breakEndsAt else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        guard !Task.isCancelled, workspace.flowTimer?.phase == .onBreak else { return }
        // A break that ran out while InkPad was closed ends quietly.
        endBreak(playSound: remaining > -5)
    }
}

/// The sound when a break is over. (No system notification: the
/// notification center crashes apps run inside Swift Playgrounds.)
enum FlowAlert {
    static func playSound() {
        AudioServicesPlaySystemSound(1005)
    }
}
