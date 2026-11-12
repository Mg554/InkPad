import Charts
import SwiftUI

/// Distraction Box settings, in UserDefaults (and synced).
enum DistractionPrefs {
    static let view = "distractionView"
    static let bubble = "distractionBubble"
    static let corner = "distractionBubbleCorner"
}

enum DistractionTab: String, CaseIterable, Identifiable {
    case jar, sort, list, insights

    var id: Self { self }

    var title: String {
        switch self {
        case .jar: "Jar"
        case .sort: "Sort"
        case .list: "List"
        case .insights: "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .jar: "takeoutbag.and.cup.and.straw"
        case .sort: "rectangle.stack"
        case .list: "list.bullet"
        case .insights: "chart.bar.xaxis"
        }
    }
}

/// What can be done with a caught thought.
@MainActor
enum DistractionActions {
    static func title(of item: Distraction) -> String {
        item.text.isEmpty ? "Distraction from \(item.createdAt.formatted(date: .abbreviated, time: .shortened))" : item.text
    }

    static func toggleDone(_ item: Distraction, in workspace: WorkspaceStore) {
        var changed = item
        changed.isDone.toggle()
        withAnimation(.snappy) { workspace.updateDistraction(changed) }
    }

    /// Into the Planner's to-do list.
    static func makeTask(_ item: Distraction, in workspace: WorkspaceStore) {
        _ = workspace.quickAdd(title(of: item), due: nil)
        var changed = item
        changed.isDone = true
        workspace.updateDistraction(changed)
        CommandCenter.shared.say("Added to the Planner")
    }

    /// Sends it to Apple Reminders (shown in InkPad's Reminders too).
    static func makeReminder(_ item: Distraction, due: Date?, in workspace: WorkspaceStore) {
        let reminders = ReminderCenter.shared
        Task {
            if reminders.access != .granted { await reminders.requestAccess() }
            guard reminders.access == .granted else {
                CommandCenter.shared.say("Allow Reminders in Settings to send it there")
                return
            }
            reminders.quickAdd(title(of: item), in: nil, due: due)
            var changed = item
            changed.isReminder = true
            changed.isDone = true
            workspace.updateDistraction(changed)
            CommandCenter.shared.say("Added to Reminders")
        }
    }

    static func delete(_ item: Distraction, in workspace: WorkspaceStore) {
        withAnimation(.snappy) { workspace.deleteDistraction(item.id) }
    }
}

// MARK: The box

/// Every caught distraction: a jar of paper balls, cards to sort, a list,
/// and insights.
struct DistractionBoxView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistractionPrefs.view) private var tabRaw = DistractionTab.jar.rawValue
    @State private var isCapturing = false

    private var tab: Binding<DistractionTab> {
        Binding(
            get: { DistractionTab(rawValue: tabRaw) ?? .jar },
            set: { new in withAnimation(.snappy) { tabRaw = new.rawValue } }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: tab) {
                    ForEach(DistractionTab.allCases) { option in
                        Label(tr(option.title), systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .themedBackground()
            .navigationTitle("Distraction Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCapturing = true
                    } label: {
                        Label("Catch", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $isCapturing) {
                DistractionCapture().environmentObject(workspace)
            }
        }
        .modifier(PageSizedSheet())
    }

    @ViewBuilder
    private var content: some View {
        switch tab.wrappedValue {
        case .jar:
            DistractionJarView(sort: { tab.wrappedValue = .sort }, capture: { isCapturing = true })
        case .sort:
            DistractionSortView()
        case .list:
            DistractionListView()
        case .insights:
            DistractionInsightsView()
        }
    }
}

// MARK: Jar

/// A glass jar; each waiting thought is a crumpled paper ball in it. New
/// ones drop in; tap one to deal with it, tap the lid to shake the jar.
struct DistractionJarView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let sort: () -> Void
    let capture: () -> Void
    @State private var shakes = 0
    @State private var picked: Distraction?

    private static let jarSize = CGSize(width: 280, height: 340)
    private static let ball: CGFloat = 21

    private var waiting: [Distraction] {
        workspace.distractions.filter { !$0.isDone }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let shown: [Distraction] = Array(waiting.prefix(48))
        ScrollView {
            VStack(spacing: 20) {
                ZStack(alignment: .top) {
                    jarGlass
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            ball(item, at: spot(index))
                        }
                    }
                    .frame(width: Self.jarSize.width - 36, height: Self.jarSize.height - 60)
                    .padding(.top, 50)
                    lid
                }
                .frame(width: Self.jarSize.width, height: Self.jarSize.height)
                .rotationEffect(.degrees(shakes % 2 == 0 ? 0 : 3), anchor: .bottom)
                .animation(.spring(response: 0.18, dampingFraction: 0.2), value: shakes)
                .animation(.spring(response: 0.6, dampingFraction: 0.62), value: shown.map(\.id))
                summary(total: waiting.count, shown: shown.count)
                HStack(spacing: 12) {
                    Button(action: capture) {
                        Label("Catch a Thought", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Button(action: sort) {
                        Label("Sort the Jar", systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(waiting.isEmpty)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func ball(_ item: Distraction, at point: CGPoint) -> some View {
        let opened: Binding<Distraction?> = Binding(
            get: { picked?.id == item.id ? picked : nil },
            set: { if $0 == nil { picked = nil } }
        )
        let drop: AnyTransition = .asymmetric(
            insertion: .offset(y: -380).combined(with: .opacity),
            removal: .scale(scale: 0.2).combined(with: .opacity)
        )
        return PaperBall(item: item, size: Self.ball * 2)
            .position(point)
            .onTapGesture { picked = item }
            .popover(item: opened) { chosen in
                DistractionDetail(item: chosen) { picked = nil }
                    .environmentObject(workspace)
            }
            .transition(drop)
    }

    /// Balls pile up from the bottom, every other row shifted half a ball.
    private func spot(_ index: Int) -> CGPoint {
        let inner: CGFloat = Self.jarSize.width - 36
        let height: CGFloat = Self.jarSize.height - 60
        let r: CGFloat = Self.ball
        let perRow: Int = max(Int(inner / (2 * r)), 1)
        let row: Int = index / perRow
        let column: Int = index % perRow
        let shift: CGFloat = row % 2 == 0 ? 0 : r * 0.9
        let jitter: CGFloat = CGFloat((index * 37) % 7) - 3
        let x: CGFloat = min(r + CGFloat(column) * 2 * r + shift + jitter, inner - r)
        let y: CGFloat = height - r - CGFloat(row) * r * 1.72 + CGFloat((index * 13) % 5)
        return CGPoint(x: x, y: max(y, r))
    }

    private var jarGlass: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 46, bottomTrailingRadius: 46, topTrailingRadius: 22, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.stroke(Color.white.opacity(0.75), lineWidth: 3))
            .overlay(shape.stroke(Color.primary.opacity(0.18), lineWidth: 1))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 8, height: 170)
                    .padding(.leading, 16)
                    .blur(radius: 1)
            }
            .padding(.top, 34)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
    }

    private var lid: some View {
        Button {
            shakes += 1
            Task {
                for _ in 0..<3 {
                    try? await Task.sleep(for: .milliseconds(120))
                    shakes += 1
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.52, blue: 0.3), Color(red: 0.5, green: 0.33, blue: 0.18)], startPoint: .top, endPoint: .bottom))
                .frame(width: Self.jarSize.width - 50, height: 34)
                .overlay {
                    HStack(spacing: 6) {
                        ForEach(0..<12, id: \.self) { _ in
                            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 2)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shake the Jar")
    }

    private func summary(total: Int, shown: Int) -> some View {
        VStack(spacing: 4) {
            if total == 0 {
                Text("The jar is empty").font(.headline)
                Text("Catch a stray thought while you focus; it lands here.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("\(total) thoughts waiting").font(.headline)
                if total > shown {
                    Text("The jar shows \(shown); sort them to see the rest.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Tap a ball to deal with it, or sort the jar after your session.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
}

/// A crumpled paper ball: yellow for typed, blue for written, green once a
/// reminder.
struct PaperBall: View {
    let item: Distraction
    let size: CGFloat

    private var paper: Color {
        if item.isReminder { return Color(red: 0.78, green: 0.93, blue: 0.78) }
        if item.ink != nil { return Color(red: 0.8, green: 0.88, blue: 1) }
        return Color(red: 1, green: 0.95, blue: 0.7)
    }

    var body: some View {
        let seed: Int = Int(item.id.uuid.1)
        Circle()
            .fill(RadialGradient(colors: [Color.white, paper, paper.opacity(0.75)], center: .topLeading, startRadius: 1, endRadius: size))
            .overlay {
                Canvas { context, canvas in
                    var creases = Path()
                    for index in 0..<4 {
                        let a: Double = Double(seed + index * 47) / 40
                        let w: Double = Double(canvas.width)
                        let h: Double = Double(canvas.height)
                        let sx: Double = w * 0.5 + Math.cosine(a) * w * 0.42
                        let sy: Double = h * 0.5 + Math.sine(a) * h * 0.42
                        let mx: Double = w * (0.3 + Double(index % 3) * 0.2)
                        let my: Double = h * (0.35 + Double(index % 2) * 0.3)
                        let start = CGPoint(x: sx, y: sy)
                        let middle = CGPoint(x: mx, y: my)
                        creases.move(to: start)
                        creases.addLine(to: middle)
                    }
                    context.stroke(creases, with: .color(.black.opacity(0.14)), lineWidth: 1)
                }
                .clipShape(Circle())
            }
            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.8))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Double(seed)))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
            .contentShape(Circle())
            .accessibilityLabel(DistractionActions.title(of: item))
    }
}

/// One thought, opened: what it says and what to do with it.
struct DistractionDetail: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let item: Distraction
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = item.ink {
                DistractionInkThumbnail(id: item.id, data: data, height: 110)
            }
            if !item.text.isEmpty {
                Text(verbatim: item.text).font(.body)
            }
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened) + (item.duringTask.map { " · " + $0 } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            actionRow("checklist", "Make a Task", .green) { DistractionActions.makeTask(item, in: workspace) }
            actionRow("bell", "Make a Reminder", .blue) { DistractionActions.makeReminder(item, due: nil, in: workspace) }
            actionRow("checkmark.circle", "Done", .secondary) { DistractionActions.toggleDone(item, in: workspace) }
            actionRow("trash", "Delete", .red) { DistractionActions.delete(item, in: workspace) }
        }
        .padding()
        .frame(width: 300)
    }

    private func actionRow(_ icon: String, _ title: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            close()
            action()
        } label: {
            Label(tr(title), systemImage: icon)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Sort

/// Cards to swipe: right makes a task, left deletes, up makes a reminder,
/// down keeps it for later.
struct DistractionSortView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var later: [UUID] = []
    @State private var offset: CGSize = .zero
    @State private var leaving = false

    private enum Choice { case task, delete, reminder, later }

    private var queue: [Distraction] {
        let waiting: [Distraction] = workspace.distractions.filter { !$0.isDone }
        let now: [Distraction] = waiting.filter { !later.contains($0.id) }
        let back: [Distraction] = later.compactMap { id in waiting.first(where: { $0.id == id }) }
        return now + back
    }

    var body: some View {
        let cards: [Distraction] = Array(queue.prefix(3))
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            if cards.isEmpty {
                ContentUnavailableView("All Sorted", systemImage: "sparkles", description: Text("No thoughts waiting. Back to what matters."))
            } else {
                ZStack {
                    ForEach(Array(cards.enumerated().reversed()), id: \.element.id) { index, item in
                        card(item, depth: index)
                    }
                }
                .frame(width: 360, height: 260)
                Text("\(queue.count) left").font(.caption).foregroundStyle(.secondary)
                buttons(cards[0])
            }
            Spacer(minLength: 0)
            hints
        }
        .padding()
    }

    private func card(_ item: Distraction, depth: Int) -> some View {
        let isTop: Bool = depth == 0
        let leaning: Choice? = isTop ? choice(for: offset) : nil
        return cardFace(item)
            .overlay {
                if let leaning {
                    badge(leaning)
                }
            }
            .shadow(color: .black.opacity(isTop ? 0.16 : 0.08), radius: isTop ? 14 : 6, y: 6)
            .scaleEffect(1 - CGFloat(depth) * 0.05)
            .offset(y: CGFloat(depth) * 14)
            .offset(isTop ? offset : .zero)
            .rotationEffect(.degrees(isTop ? Double(offset.width / 22) : 0))
            .allowsHitTesting(isTop)
            .gesture(cardDrag(item))
    }

    private func cardFace(_ item: Distraction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = item.ink {
                DistractionInkThumbnail(id: item.id, data: data, height: 120)
            }
            if !item.text.isEmpty {
                Text(verbatim: item.text).font(.title3.weight(.medium)).lineLimit(5)
            }
            Spacer(minLength: 0)
            HStack {
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let task = item.duringTask { Text(verbatim: "· " + task).lineLimit(1) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 340, height: 230, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cardDrag(_ item: Distraction) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !leaving else { return }
                offset = value.translation
            }
            .onEnded { value in
                let extraX: CGFloat = (value.predictedEndTranslation.width - value.translation.width) * 0.3
                let extraY: CGFloat = (value.predictedEndTranslation.height - value.translation.height) * 0.3
                let landing = CGSize(width: value.translation.width + extraX, height: value.translation.height + extraY)
                if let chosen = choice(for: landing) {
                    send(item, chosen)
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { offset = .zero }
                }
            }
    }

    private func choice(for drag: CGSize) -> Choice? {
        let horizontal: Bool = abs(drag.width) > abs(drag.height)
        if horizontal {
            if drag.width > 110 { return .task }
            if drag.width < -110 { return .delete }
        } else {
            if drag.height < -90 { return .reminder }
            if drag.height > 90 { return .later }
        }
        return nil
    }

    private func badge(_ choice: Choice) -> some View {
        let info: (String, String, Color) = describe(choice)
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(info.2.opacity(0.14))
            .overlay {
                Label(tr(info.1), systemImage: info.0)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(info.2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(info.2, lineWidth: 2.5))
                    .rotationEffect(.degrees(-8))
            }
            .allowsHitTesting(false)
    }

    private func describe(_ choice: Choice) -> (String, String, Color) {
        switch choice {
        case .task: ("checklist", "Task", .green)
        case .delete: ("trash", "Delete", .red)
        case .reminder: ("bell", "Reminder", .blue)
        case .later: ("clock", "Later", .gray)
        }
    }

    /// The card flies off in its direction, then the choice is made.
    private func send(_ item: Distraction, _ choice: Choice) {
        leaving = true
        let away: CGSize
        switch choice {
        case .task: away = CGSize(width: 900, height: offset.height)
        case .delete: away = CGSize(width: -900, height: offset.height)
        case .reminder: away = CGSize(width: offset.width, height: -900)
        case .later: away = CGSize(width: offset.width, height: 900)
        }
        withAnimation(.easeIn(duration: 0.22)) { offset = away }
        Task {
            try? await Task.sleep(for: .milliseconds(230))
            switch choice {
            case .task: DistractionActions.makeTask(item, in: workspace)
            case .delete: DistractionActions.delete(item, in: workspace)
            case .reminder: DistractionActions.makeReminder(item, due: nil, in: workspace)
            case .later:
                later.removeAll { $0 == item.id }
                later.append(item.id)
            }
            offset = .zero
            leaving = false
        }
    }

    private func buttons(_ top: Distraction) -> some View {
        HStack(spacing: 14) {
            sortButton(.delete, top)
            sortButton(.later, top)
            sortButton(.reminder, top)
            sortButton(.task, top)
        }
    }

    private func sortButton(_ choice: Choice, _ item: Distraction) -> some View {
        let info: (String, String, Color) = describe(choice)
        return Button {
            guard !leaving else { return }
            send(item, choice)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: info.0).font(.title2)
                Text(tr(info.1)).font(.caption.weight(.semibold))
            }
            .foregroundStyle(info.2)
            .frame(width: 74, height: 64)
            .background(info.2.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableStyle())
    }

    private var hints: some View {
        HStack(spacing: 18) {
            Label("Task", systemImage: "arrow.right")
            Label("Delete", systemImage: "arrow.left")
            Label("Reminder", systemImage: "arrow.up")
            Label("Later", systemImage: "arrow.down")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: List

/// Every thought in a list, with Show Done.
struct DistractionListView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var showsDone = false

    private var shown: [Distraction] {
        workspace.distractions.filter { showsDone || !$0.isDone }
    }

    var body: some View {
        List {
            Toggle("Show Done", isOn: $showsDone)
            if shown.isEmpty {
                Text("Nothing here. Catch a thought with + while you focus.").foregroundStyle(.secondary)
            }
            ForEach(shown) { item in
                row(item)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: Distraction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                DistractionActions.toggleDone(item, in: workspace)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 6) {
                if let data = item.ink {
                    DistractionInkThumbnail(id: item.id, data: data)
                }
                if !item.text.isEmpty {
                    Text(verbatim: item.text).strikethrough(item.isDone)
                }
                HStack(spacing: 8) {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let task = item.duringTask { Text(verbatim: "· " + task).lineLimit(1) }
                    if item.isReminder { Label("Reminder", systemImage: "bell.fill").foregroundStyle(Color.inkAccent) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    DistractionActions.makeTask(item, in: workspace)
                } label: {
                    Label("Make a Task", systemImage: "checklist")
                }
                Button {
                    DistractionActions.makeReminder(item, due: nil, in: workspace)
                } label: {
                    Label("Make a Reminder", systemImage: "bell")
                }
                Button {
                    DistractionActions.makeReminder(item, due: Calendar.current.date(byAdding: .day, value: 1, to: Date()), in: workspace)
                } label: {
                    Label("Remind Me Tomorrow", systemImage: "sunrise")
                }
                Button(role: .destructive) {
                    DistractionActions.delete(item, in: workspace)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                DistractionActions.delete(item, in: workspace)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: Insights

/// When and during what thoughts wander, and the run of sessions without one.
struct DistractionInsightsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    private struct HourCount: Identifiable {
        let hour: Int
        let count: Int
        var id: Int { hour }
    }

    private struct DayCount: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    var body: some View {
        let calendar = Calendar.current
        let twoWeeks: Date = Date().addingTimeInterval(-14 * 86_400)
        let recent: [Distraction] = workspace.distractions.filter { $0.createdAt >= twoWeeks }
        let sessions: [FlowSession] = workspace.flowSessions.filter { $0.endedAt >= twoWeeks }.sorted { $0.endedAt < $1.endedAt }
        let calm: [Bool] = sessions.map { session in
            !workspace.distractions.contains { $0.createdAt >= session.startedAt && $0.createdAt <= session.endedAt }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tiles(recent: recent, calm: calm)
                if !calm.isEmpty { sessionDots(calm) }
                chartCard("By Hour (Last 2 Weeks)") {
                    Chart(hours(recent, calendar: calendar)) { item in
                        BarMark(x: .value("Hour", item.hour), y: .value("Thoughts", item.count))
                            .foregroundStyle(Color.orange.gradient)
                            .cornerRadius(3)
                    }
                    .chartXScale(domain: 0...23)
                    .frame(height: 160)
                }
                chartCard("Last 7 Days") {
                    Chart(days(calendar: calendar)) { item in
                        BarMark(x: .value("Day", item.day, unit: .day), y: .value("Thoughts", item.count))
                            .foregroundStyle(Color.inkAccent.gradient)
                            .cornerRadius(4)
                    }
                    .frame(height: 150)
                }
                topTasks(recent)
            }
            .padding(20)
        }
    }

    private func tiles(recent: [Distraction], calm: [Bool]) -> some View {
        let today: Int = workspace.distractions.filter { Calendar.current.isDateInToday($0.createdAt) }.count
        let waiting: Int = workspace.distractions.filter { !$0.isDone }.count
        var streak = 0
        for value in calm.reversed() {
            if value { streak += 1 } else { break }
        }
        return HStack(spacing: 12) {
            tile("\(today)", "today", .orange)
            tile("\(recent.count)", "in 2 weeks", .primary)
            tile("\(waiting)", "waiting", .blue)
            tile("\(streak)", "calm sessions in a row", .green)
        }
    }

    private func tile(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value).font(.title.bold()).foregroundStyle(tint)
            Text(tr(label)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    /// One dot per recent session: green without a distraction, orange with.
    private func sessionDots(_ calm: [Bool]) -> some View {
        let calmCount: Int = calm.filter { $0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(calmCount) of \(calm.count) sessions had no distractions").font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                ForEach(Array(calm.suffix(30).enumerated()), id: \.offset) { _, value in
                    Circle()
                        .fill(value ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr(title)).font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private func hours(_ items: [Distraction], calendar: Calendar) -> [HourCount] {
        var counts: [Int: Int] = [:]
        for item in items { counts[calendar.component(.hour, from: item.createdAt), default: 0] += 1 }
        return counts.map { HourCount(hour: $0.key, count: $0.value) }.sorted { $0.hour < $1.hour }
    }

    private func days(calendar: Calendar) -> [DayCount] {
        let today: Date = calendar.startOfDay(for: Date())
        var result: [DayCount] = []
        for back in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let count: Int = workspace.distractions.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }.count
            result.append(DayCount(day: day, count: count))
        }
        return result
    }

    private func taskCounts(_ items: [Distraction]) -> [(key: String, value: Int)] {
        var byTask: [String: Int] = [:]
        for item in items {
            if let task = item.duringTask { byTask[task, default: 0] += 1 }
        }
        return Array(byTask.sorted { $0.value > $1.value }.prefix(5))
    }

    @ViewBuilder
    private func topTasks(_ items: [Distraction]) -> some View {
        let top: [(key: String, value: Int)] = taskCounts(items)
        let most: Int = top.first?.value ?? 1
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Most Distracted While Working On").font(.subheadline.weight(.semibold))
                ForEach(top, id: \.key) { entry in
                    HStack(spacing: 10) {
                        Text(verbatim: entry.key).font(.callout).lineLimit(1).frame(width: 160, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.orange.gradient)
                                .frame(width: max(proxy.size.width * CGFloat(entry.value) / CGFloat(most), 8))
                        }
                        .frame(height: 12)
                        Text(verbatim: "\(entry.value)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
    }
}

// MARK: Floating bubble

/// While focusing, a small bubble waits in a corner: tap it to catch a
/// thought, drag it to another corner.
struct FloatingCatchBubble: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @AppStorage(DistractionPrefs.corner) private var corner = 3
    @State private var drag: CGSize = .zero
    @State private var pulse = false

    /// Caught during the work running now.
    private var caught: Int {
        guard let timer = workspace.flowTimer, timer.phase == .working else { return 0 }
        return workspace.distractions.filter { $0.createdAt >= timer.workStartedAt }.count
    }

    var body: some View {
        GeometryReader { proxy in
            let spot: CGPoint = position(corner, in: proxy.size)
            bubble
                .position(x: spot.x + drag.width, y: spot.y + drag.height)
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let x: CGFloat = spot.x + value.predictedEndTranslation.width
                        let y: CGFloat = spot.y + value.predictedEndTranslation.height
                        let right: Bool = x > proxy.size.width / 2
                        let bottom: Bool = y > proxy.size.height / 2
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                            corner = (bottom ? 2 : 0) + (right ? 1 : 0)
                            drag = .zero
                        }
                    })
        }
        .onChange(of: caught) {
            pulse = true
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                pulse = false
            }
        }
    }

    private func position(_ corner: Int, in size: CGSize) -> CGPoint {
        let right: Bool = corner % 2 == 1
        let bottom: Bool = corner >= 2
        return CGPoint(x: right ? size.width - 44 : 44, y: bottom ? size.height - 120 : 110)
    }

    private var bubble: some View {
        Button {
            CommandCenter.shared.sheet = .catchDistraction
        } label: {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.orange.gradient))
                .overlay(alignment: .topTrailing) {
                    if caught > 0 {
                        Text(verbatim: "\(caught)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Color.red))
                            .offset(x: 4, y: -4)
                    }
                }
                .shadow(color: .orange.opacity(0.45), radius: pulse ? 16 : 8)
                .scaleEffect(pulse ? 1.18 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulse)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Catch a Distraction")
    }
}

/// Settings › Focus › Distraction Box.
struct DistractionSettingsView: View {
    @AppStorage(DistractionPrefs.view) private var tabRaw = DistractionTab.jar.rawValue
    @AppStorage(DistractionPrefs.bubble) private var bubble = true

    var body: some View {
        Form {
            Section {
                Picker("Opens On", selection: $tabRaw) {
                    ForEach(DistractionTab.allCases) { Label(tr($0.title), systemImage: $0.systemImage).tag($0.rawValue) }
                }
            }
            Section {
                Toggle("Floating Catch Bubble", isOn: $bubble)
            } footer: {
                Text("While a focus session runs, a small bubble waits in a corner: tap it to catch a thought by writing, typing or speaking. Drag it to another corner.")
            }
        }
        .navigationTitle("Distraction Box")
        .navigationBarTitleDisplayMode(.inline)
    }
}
