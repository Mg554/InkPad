import EventKit
import SwiftUI

/// Apple Reminders, read and written with EventKit. Reminders stay in the
/// Reminders app's own store (so they sync to your other iPads through
/// iCloud, and its alerts work), and InkPad can link one to a note.
@MainActor
final class ReminderCenter: ObservableObject {
    static let shared = ReminderCenter()

    enum Access {
        case unknown, granted, denied
    }

    /// The smart lists at the top, like the Reminders app.
    enum SmartList: String, CaseIterable, Identifiable {
        case today, scheduled, all, priority, completed

        var id: Self { self }

        var title: String {
            switch self {
            case .today: "Today"
            case .scheduled: "Scheduled"
            case .all: "All"
            case .priority: "Priority"
            case .completed: "Completed"
            }
        }

        var systemImage: String {
            switch self {
            case .today: "calendar.circle.fill"
            case .scheduled: "calendar.badge.clock"
            case .all: "tray.circle.fill"
            case .priority: "exclamationmark.circle.fill"
            case .completed: "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .today: .blue
            case .scheduled: .red
            case .all: .gray
            case .priority: .orange
            case .completed: .green
            }
        }
    }

    let eventStore = EKEventStore()
    @Published private(set) var access: Access = .unknown
    @Published private(set) var lists: [EKCalendar] = []
    /// Reminders not done yet, in every list.
    @Published private(set) var open: [EKReminder] = []
    /// Done in the last 30 days.
    @Published private(set) var completed: [EKReminder] = []
    @Published var errorMessage: String?

    private var observer: NSObjectProtocol?

    private init() {
        updateAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func requestAccess() async {
        do {
            _ = try await eventStore.requestFullAccessToReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
        updateAccess()
        await refresh()
    }

    func refresh() async {
        guard access == .granted else { return }
        lists = eventStore.calendars(for: .reminder)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let openPredicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let donePredicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
            ending: nil,
            calendars: nil
        )
        open = await fetch(openPredicate)
        completed = await fetch(donePredicate).sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: Queries

    func reminders(in smart: SmartList) -> [EKReminder] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        switch smart {
        case .today:
            return open.filter { ($0.dueDate ?? .distantFuture) < endOfToday }.sorted(by: Self.byDue)
        case .scheduled:
            return open.filter { $0.dueDate != nil }.sorted(by: Self.byDue)
        case .all:
            return open.sorted(by: Self.byDue)
        case .priority:
            return open.filter { $0.priority != 0 }.sorted { $0.priority < $1.priority }
        case .completed:
            return completed
        }
    }

    func reminders(in list: EKCalendar) -> [EKReminder] {
        open.filter { $0.calendar.calendarIdentifier == list.calendarIdentifier }.sorted(by: Self.byDue)
    }

    /// Reminders linked to a note.
    func reminders(linkedTo noteID: UUID) -> [EKReminder] {
        open.filter { $0.linkedNoteID == noteID }
    }

    private static func byDue(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?): left < right
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
        }
    }

    // MARK: Changes

    func newReminder(in list: EKCalendar? = nil) -> EKReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list ?? eventStore.defaultCalendarForNewReminders() ?? lists.first
        return reminder
    }

    @discardableResult
    func save(_ reminder: EKReminder) -> Bool {
        guard reminder.calendar != nil else {
            errorMessage = "Make a list in Reminders first."
            return false
        }
        do {
            try eventStore.save(reminder, commit: true)
            Task { await refresh() }
            return true
        } catch {
            errorMessage = "Could not save the reminder: \(error.localizedDescription)"
            return false
        }
    }

    func quickAdd(_ title: String, in list: EKCalendar?, due: Date? = nil) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let reminder = newReminder(in: list)
        reminder.title = text
        if let due { reminder.setDue(due, hasTime: false) }
        save(reminder)
    }

    func toggle(_ reminder: EKReminder) {
        reminder.isCompleted.toggle()
        save(reminder)
    }

    func delete(_ reminder: EKReminder) {
        do {
            try eventStore.remove(reminder, commit: true)
            Task { await refresh() }
        } catch {
            errorMessage = "Could not delete the reminder: \(error.localizedDescription)"
        }
    }

    func addList(named name: String, color: Color) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = title
        list.cgColor = UIColor(color).cgColor
        list.source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first { $0.sourceType == .calDAV || $0.sourceType == .local }
        do {
            try eventStore.saveCalendar(list, commit: true)
            Task { await refresh() }
        } catch {
            errorMessage = "Could not add the list: \(error.localizedDescription)"
        }
    }

    func updateList(_ list: EKCalendar, name: String, color: Color) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { list.title = title }
        list.cgColor = UIColor(color).cgColor
        do {
            try eventStore.saveCalendar(list, commit: true)
            Task { await refresh() }
        } catch {
            errorMessage = "Could not change the list: \(error.localizedDescription)"
        }
    }

    func deleteList(_ list: EKCalendar) {
        do {
            try eventStore.removeCalendar(list, commit: true)
            Task { await refresh() }
        } catch {
            errorMessage = "Could not delete the list: \(error.localizedDescription)"
        }
    }
}

extension EKReminder {
    var dueDate: Date? { dueDateComponents?.date ?? dueDateComponents.flatMap { Calendar.current.date(from: $0) } }

    /// True when the due date has a time, not just a day.
    var hasDueTime: Bool { dueDateComponents?.hour != nil }

    func setDue(_ date: Date?, hasTime: Bool) {
        guard let date else {
            dueDateComponents = nil
            alarms?.forEach { removeAlarm($0) }
            return
        }
        let units: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        var components = Calendar.current.dateComponents(units, from: date)
        components.calendar = Calendar.current
        components.timeZone = hasTime ? TimeZone.current : nil
        dueDateComponents = components
    }

    /// The note this reminder was made from (`inkpad://id/<uuid>`).
    var linkedNoteID: UUID? {
        guard let url, url.scheme == InkPadLink.scheme, url.host == "id" else { return nil }
        return UUID(uuidString: String(url.path.dropFirst()))
    }

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return hasDueTime ? dueDate < Date() : dueDate < Calendar.current.startOfDay(for: Date())
    }

    var listColor: Color { calendar.map { Color(cgColor: $0.cgColor) } ?? .inkAccent }

    /// "!!!" for high, "!!" medium, "!" low, as in Reminders.
    var priorityMarks: String {
        switch priority {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: ""
        }
    }
}
