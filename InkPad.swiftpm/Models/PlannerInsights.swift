import Foundation

/// What the Planner learns from Flowmodoro: how long tasks really take,
/// the hours of best focus, a plan for the day, and the week in numbers.
enum PlannerInsights {
    // MARK: Estimates

    /// Actual focus time over estimated time, from finished tasks that have
    /// both (1.5 means tasks take half again as long as planned). `nil`
    /// until there are at least two.
    static func estimateFactor(_ tasks: [PlanTask]) -> Double? {
        var estimated = 0
        var actual = 0
        var count = 0
        for task in tasks where task.status == .done {
            guard let minutes = task.estimateMinutes, minutes > 0, let seconds = task.focusSeconds, seconds > 0 else { continue }
            estimated += minutes * 60
            actual += seconds
            count += 1
        }
        guard count >= 2, estimated > 0 else { return nil }
        return Double(actual) / Double(estimated)
    }

    /// An estimate corrected by what the history shows.
    static func suggestedMinutes(_ estimate: Int, factor: Double?) -> Int {
        guard let factor else { return estimate }
        let corrected: Double = Double(estimate) * factor
        let rounded = Int((corrected / 5).rounded()) * 5
        return max(rounded, 5)
    }

    // MARK: Focus hours

    /// Seconds of focus that started in each hour of the day, over the last days.
    static func focusByHour(_ sessions: [FlowSession], days: Int = 30) -> [Int] {
        var hours = Array(repeating: 0, count: 24)
        let since = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let calendar = Calendar.current
        for session in sessions where session.endedAt >= since {
            let hour = calendar.component(.hour, from: session.startedAt)
            hours[hour] += session.workSeconds
        }
        return hours
    }

    /// The hours with the most focus, best first (empty without history).
    static func bestHours(_ byHour: [Int], count: Int = 3) -> [Int] {
        let ranked = byHour.indices.filter { byHour[$0] > 0 }.sorted { byHour[$0] > byHour[$1] }
        return Array(ranked.prefix(count))
    }

    // MARK: Plan My Day

    /// Tasks worth planning today: due today or before, high priority, or in progress.
    static func todayCandidates(_ tasks: [PlanTask], now: Date = Date()) -> [PlanTask] {
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
        return tasks.filter { task in
            guard task.status != .done else { return false }
            let isDue: Bool = task.dueDate.map { $0 < endOfToday } ?? false
            let isScheduled: Bool = task.scheduledAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false
            return isDue || isScheduled || task.priority == .high || task.status == .inProgress
        }
    }

    /// Minutes a task needs in a plan.
    static func plannedMinutes(_ task: PlanTask, factor: Double?) -> Int {
        let estimate = task.estimateMinutes ?? 30
        let remaining = estimate * 60 - (task.focusSeconds ?? 0)
        let left = max(remaining / 60, 15)
        return suggestedMinutes(left, factor: factor)
    }

    /// Time blocks from now until `endHour`: the hardest tasks (important,
    /// then long) go into the hours of best focus, with breaks between.
    static func planDay(tasks: [PlanTask], sessions: [FlowSession], breakShare: Int, now: Date = Date(), endHour: Int = 22) -> [UUID: Date] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let start = (nowMinute + 14) / 15 * 15
        let end = endHour * 60
        guard start < end else { return [:] }
        let factor = estimateFactor(tasks)
        let best = bestHours(focusByHour(sessions))
        let ordered = todayCandidates(tasks, now: now).sorted { a, b in
            if a.important != b.important { return a.important }
            return plannedMinutes(a, factor: factor) > plannedMinutes(b, factor: factor)
        }
        var busy: [ClosedRange<Int>] = []
        var plan: [UUID: Date] = [:]
        for task in ordered {
            let length = plannedMinutes(task, factor: factor)
            let rest = max(length * breakShare / 100, 5)
            // Try the best hours first, then the first free time.
            // A best hour that has already begun still counts from now.
            var tries: [Int] = []
            for hour in best where hour * 60 + 60 > start {
                tries.append(max(hour * 60, start))
            }
            tries.append(start)
            var placed: Int?
            for first in tries {
                if let slot = freeSlot(from: first, length: length + rest, end: end, busy: busy) {
                    placed = slot
                    break
                }
            }
            guard let slot = placed else { continue }
            busy.append(slot...(slot + length + rest - 1))
            // By the calendar, so a daylight-saving day is right too.
            if let date = calendar.date(bySettingHour: slot / 60, minute: slot % 60, second: 0, of: dayStart) {
                plan[task.id] = date
            }
        }
        return plan
    }

    private static func freeSlot(from first: Int, length: Int, end: Int, busy: [ClosedRange<Int>]) -> Int? {
        var candidate = first
        while candidate + length <= end {
            let range = candidate...(candidate + length - 1)
            if let clash = busy.first(where: { $0.overlaps(range) }) {
                candidate = (clash.upperBound + 1 + 4) / 5 * 5
            } else {
                return candidate
            }
        }
        return nil
    }

    // MARK: Weekly Review

    struct Week {
        /// Focus seconds for each of the last 7 days, oldest first.
        var focusPerDay: [Int]
        var dayStarts: [Date]
        var totalFocus: Int
        var tasksDone: Int
        var distractions: Int
        /// Tasks with the most focus this week.
        var topTasks: [(title: String, seconds: Int)]
        var bestHour: Int?
        var estimateFactor: Double?
        var sessions: Int
    }

    static func week(tasks: [PlanTask], sessions: [FlowSession], distractions: [Distraction], now: Date = Date()) -> Week {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var starts: [Date] = []
        for back in (0..<7).reversed() {
            starts.append(calendar.date(byAdding: .day, value: -back, to: today) ?? today)
        }
        let weekStart = starts[0]
        var perDay = Array(repeating: 0, count: 7)
        var byTask: [String: Int] = [:]
        var count = 0
        for session in sessions where session.endedAt >= weekStart {
            let day = calendar.startOfDay(for: session.endedAt)
            if let index = starts.firstIndex(of: day) { perDay[index] += session.workSeconds }
            byTask[session.taskTitle, default: 0] += session.workSeconds
            count += 1
        }
        let ranked: [(key: String, value: Int)] = byTask.sorted { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in
            a.value > b.value
        }
        var top: [(title: String, seconds: Int)] = []
        for item in ranked.prefix(5) { top.append((title: item.key, seconds: item.value)) }
        let done = tasks.filter { ($0.completedAt ?? .distantPast) >= weekStart }.count
        let caught = distractions.filter { $0.createdAt >= weekStart }.count
        let hours = focusByHour(sessions, days: 7)
        return Week(
            focusPerDay: perDay,
            dayStarts: starts,
            totalFocus: perDay.reduce(0, +),
            tasksDone: done,
            distractions: caught,
            topTasks: top,
            bestHour: bestHours(hours, count: 1).first,
            estimateFactor: estimateFactor(tasks),
            sessions: count
        )
    }

    /// "9 AM"-style hour label.
    static func hourLabel(_ hour: Int) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: today) ?? today
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "1 h 25 min" or "25 min".
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
