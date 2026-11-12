import EventKit
import SwiftUI

/// One thing the command palette can do.
struct PaletteItem: Identifiable {
    enum Section: Int, CaseIterable {
        case suggested, thisNote, create, goTo, notes, settings, ai

        var title: String {
            switch self {
            case .suggested: "Do It"
            case .thisNote: "This Note"
            case .create: "Create"
            case .goTo: "Go To"
            case .notes: "Notes"
            case .settings: "Settings"
            case .ai: "Ask AI"
            }
        }
    }

    let id: String
    let title: String
    var subtitle: String?
    let systemImage: String
    var tint: Color = .inkAccent
    /// Shown on the right, like "⌘N".
    var shortcut: String?
    let section: Section
    /// Extra words it answers to (Arabic too).
    var keywords: [String] = []
    /// False when the item only fills in the search field.
    var closesPalette = true
    let run: @MainActor () -> Void
}

/// Sheets the palette asks the library to show.
enum CommandSheet: Identifiable {
    case themes
    case history(NoteSummary)
    case reminder(ReminderDraft)
    /// Living Notes: everything written about a concept.
    case concept(String)
    /// Distraction Box, and catching one.
    case distractions
    case catchDistraction

    var id: String {
        switch self {
        case .distractions: "distractions"
        case .catchDistraction: "catch-distraction"
        case .themes: "themes"
        case let .history(note): "history-\(note.id)"
        case let .reminder(draft): "reminder-\(draft.id)"
        case let .concept(key): "concept-\(key)"
        }
    }
}

/// Opens and runs the command palette from anywhere (⌘K, the floating
/// button, or a three-finger swipe down).
@MainActor
final class CommandCenter: ObservableObject {
    static let shared = CommandCenter()

    @Published var isPresented = false
    /// Text to start the palette with (from shortcuts like ⌘⇧R).
    @Published var prefill = ""
    @Published var sheet: CommandSheet?
    /// A short confirmation shown at the bottom ("Reminder added…").
    @Published var toast: String?
    /// Commands of the note that is open, if any.
    @Published private(set) var noteCommands: (noteID: UUID, items: [PaletteItem])?

    /// Set by the library view.
    var navigate: (LibraryScope) -> Void = { _ in }
    var openNote: (UUID) -> Void = { _ in }
    /// A page to show when a note opens (a task made from a sticky note).
    private var pendingPages: [UUID: Int] = [:]

    func openNote(_ id: UUID, page: Int) {
        pendingPages[id] = page
        openNote(id)
    }

    /// The page asked for when this note was opened, once.
    func takePendingPage(for id: UUID) -> Int? {
        pendingPages.removeValue(forKey: id)
    }

    /// A book's PDF page (zero-based) to show when it opens (Knowledge GPS).
    private var pendingPDFPages: [UUID: Int] = [:]

    func openNote(_ id: UUID, pdfPage: Int) {
        pendingPDFPages[id] = pdfPage
        openNote(id)
    }

    func takePendingPDFPage(for id: UUID) -> Int? {
        pendingPDFPages.removeValue(forKey: id)
    }

    /// A note to open beside this one when it opens (a saved workspace).
    private var pendingBeside: [UUID: UUID] = [:]

    func openNote(_ id: UUID, beside other: UUID) {
        pendingBeside[id] = other
        openNote(id)
    }

    func takePendingBeside(for id: UUID) -> UUID? {
        pendingBeside.removeValue(forKey: id)
    }

    private static let recentKey = "paletteRecent"
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    private var toastTask: Task<Void, Never>?

    /// Focus Mode on its own screen.
    @Published var showsFocusScreen = false

    func show(prefill text: String = "") {
        prefill = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isPresented = true }
    }

    func hide() {
        // Let go of the keyboard before the field goes away.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isPresented = false }
    }

    func toggle() {
        isPresented ? hide() : show()
    }

    func register(noteID: UUID, items: [PaletteItem]) {
        noteCommands = (noteID, items)
    }

    func unregister(noteID: UUID) {
        if noteCommands?.noteID == noteID { noteCommands = nil }
    }

    func run(_ item: PaletteItem) {
        if item.closesPalette {
            hide()
            remember(item.id)
        }
        item.run()
    }

    private func remember(_ id: String) {
        // Only stable commands are worth remembering.
        guard !id.hasPrefix("intent-"), !id.hasPrefix("ai-") else { return }
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recent = Array(recent.prefix(6))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    func say(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.toast = nil }
        }
    }

    // MARK: Doing what a sentence asked

    func perform(_ intent: CommandIntent, store: LibraryStore, workspace: WorkspaceStore) {
        switch intent {
        case let .reminder(title, due, hasTime):
            Task { await addReminder(title: title, due: due, hasTime: hasTime) }
        case let .task(title, due):
            workspace.save(PlanTask(title: title.isEmpty ? "New Task" : title, dueDate: due))
            say("Task added to the Planner" + (due.map { ", due \(Self.dayText($0, hasTime: false))" } ?? ""))
        case let .expense(title, amount, category, isIncome):
            var expense = Expense(kind: isIncome ? .income : .expense)
            expense.amount = amount
            expense.title = title
            expense.category = category
            workspace.save(expense)
            say("\(isIncome ? "Income" : "Expense") of \(workspace.money.string(amount)) added (\(category.title))")
        case let .note(title):
            let theme = ThemeSettings.current
            if let note = store.createNote(in: nil, template: .lined, paper: theme.paperForNewNotes ? theme.paper : .white) {
                if !title.isEmpty { store.renameNote(note.id, to: title) }
                openNote(note.id)
            }
        case let .textNote(title):
            if let note = store.createTextNote(titled: title.isEmpty ? "Untitled" : title, in: nil) {
                openNote(note.id)
            }
        case let .mindMap(title):
            workspace.save(MindMap(title: title.isEmpty ? "Central Idea" : title))
            navigate(.mindMaps)
            say("Mind map \"\(title.isEmpty ? "Central Idea" : title)\" made")
        }
    }

    private func addReminder(title: String, due: Date?, hasTime: Bool) async {
        let reminders = ReminderCenter.shared
        if reminders.access != .granted { await reminders.requestAccess() }
        guard reminders.access == .granted else {
            say("Allow InkPad to use Reminders in Settings first")
            return
        }
        let reminder = reminders.newReminder()
        reminder.title = title.isEmpty ? "Reminder" : title
        if let due {
            reminder.setDue(due, hasTime: hasTime)
            if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        if reminders.save(reminder) {
            say("Reminder added" + (due.map { " for \(Self.dayText($0, hasTime: hasTime))" } ?? ""))
        }
    }

    /// How an intent reads in the palette, like "Reminder: Call Sara · Tomorrow 9:00".
    static func describe(_ intent: CommandIntent, money: MoneyFormatter) -> (title: String, subtitle: String, systemImage: String, tint: Color) {
        switch intent {
        case let .reminder(title, due, hasTime):
            return ("Remind Me: \(title.isEmpty ? "Reminder" : title)", due.map { dayText($0, hasTime: hasTime) } ?? "No date", "bell.badge", .orange)
        case let .task(title, due):
            return ("Add Task: \(title.isEmpty ? "New Task" : title)", due.map { "Due \(dayText($0, hasTime: false))" } ?? "Planner", "checklist", .blue)
        case let .expense(title, amount, category, isIncome):
            return ("\(isIncome ? "Add Income" : "Add Expense"): \(money.string(amount))", [title, category.title].filter { !$0.isEmpty }.joined(separator: " · "), isIncome ? "plus.circle" : "creditcard", isIncome ? .green : .red)
        case let .note(title):
            return ("New Note: \(title.isEmpty ? "Untitled" : title)", "Handwritten", "square.and.pencil", .purple)
        case let .textNote(title):
            return ("New Text Note: \(title.isEmpty ? "Untitled" : title)", "Markdown", "doc.text", .purple)
        case let .mindMap(title):
            return ("New Mind Map: \(title.isEmpty ? "Central Idea" : title)", "Mind Maps", "point.3.connected.trianglepath.dotted", .pink)
        }
    }

    static func dayText(_ date: Date, hasTime: Bool) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today"
            : calendar.isDateInTomorrow(date) ? "Tomorrow"
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return hasTime ? "\(day) \(date.formatted(date: .omitted, time: .shortened))" : day
    }
}

extension View {
    /// Offers these commands in the palette while this note is open.
    func paletteNoteCommands(_ noteID: UUID, _ items: @escaping () -> [PaletteItem]) -> some View {
        onAppear { CommandCenter.shared.register(noteID: noteID, items: items()) }
            .onDisappear { CommandCenter.shared.unregister(noteID: noteID) }
    }
}
