import EventKit
import SwiftUI

/// A reminder being added or edited.
struct ReminderDraft: Identifiable {
    let id = UUID()
    let reminder: EKReminder
    var isNew = false
}

/// Title, notes, date and time (with an alert), priority, list and the
/// note it belongs to.
struct ReminderEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var center = ReminderCenter.shared
    @Environment(\.dismiss) private var dismiss

    let draft: ReminderDraft

    @State private var title: String
    @State private var notes: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var due: Date
    @State private var alerts: Bool
    @State private var priority: Int
    @State private var listID: String
    @State private var noteID: UUID?

    init(draft: ReminderDraft) {
        self.draft = draft
        let reminder = draft.reminder
        _title = State(initialValue: reminder.title ?? "")
        _notes = State(initialValue: reminder.notes ?? "")
        _hasDate = State(initialValue: reminder.dueDate != nil)
        _hasTime = State(initialValue: reminder.hasDueTime)
        _due = State(initialValue: reminder.dueDate ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
        _alerts = State(initialValue: !(reminder.alarms ?? []).isEmpty)
        _priority = State(initialValue: Self.level(of: reminder.priority))
        _listID = State(initialValue: reminder.calendar?.calendarIdentifier ?? "")
        _noteID = State(initialValue: reminder.linkedNoteID)
    }

    /// EventKit priority (1 high, 5 medium, 9 low) as 0 none … 3 high.
    private static func level(of priority: Int) -> Int {
        switch priority {
        case 1...4: 3
        case 5: 2
        case 6...9: 1
        default: 0
        }
    }

    private static let priorities = [(0, "None"), (1, "Low"), (2, "Medium"), (3, "High")]
    private static let eventKitPriority = [0, 9, 5, 1]

    private var isNew: Bool { draft.isNew }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Toggle(isOn: $hasDate.animation()) {
                        Label("Date", systemImage: "calendar")
                    }
                    if hasDate {
                        DatePicker("Day", selection: $due, displayedComponents: .date)
                        Toggle(isOn: $hasTime.animation()) {
                            Label("Time", systemImage: "clock")
                        }
                        if hasTime {
                            DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                            Toggle(isOn: $alerts) {
                                Label("Alert at This Time", systemImage: "bell")
                            }
                        }
                    }
                } footer: {
                    if hasDate && hasTime && alerts {
                        Text("The Reminders app shows the alert, even when InkPad is closed.")
                    }
                }
                Section {
                    Picker(selection: $priority) {
                        ForEach(Self.priorities, id: \.0) { level in
                            Text(level.1).tag(level.0)
                        }
                    } label: {
                        Label("Priority", systemImage: "exclamationmark")
                    }
                    Picker(selection: $listID) {
                        ForEach(center.lists, id: \.calendarIdentifier) { list in
                            Text(tr(list.title)).tag(list.calendarIdentifier)
                        }
                    } label: {
                        Label("List", systemImage: "list.bullet")
                    }
                    Picker(selection: $noteID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.notes(in: .allNotes)) { note in
                            Text(tr(note.title)).tag(UUID?.some(note.id))
                        }
                    } label: {
                        Label("Note", systemImage: "doc.text")
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete Reminder", role: .destructive) {
                            center.delete(draft.reminder)
                            dismiss()
                        }
                    }
                }
            }
            .overlay {
                if center.access == .denied {
                    ContentUnavailableView(
                        "No Access to Reminders",
                        systemImage: "lock",
                        description: Text("Allow InkPad in Settings › Privacy & Security › Reminders (Full Access).")
                    )
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .task {
                if center.access == .unknown { await center.requestAccess() }
                if listID.isEmpty, let list = center.newReminder().calendar {
                    listID = list.calendarIdentifier
                }
            }
            .navigationTitle(isNew ? "New Reminder" : "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let reminder = draft.reminder
        reminder.title = title.trimmingCharacters(in: .whitespaces)
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.setDue(hasDate ? due : nil, hasTime: hasTime)
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        if hasDate, hasTime, alerts {
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        reminder.priority = Self.eventKitPriority[priority]
        if let list = center.lists.first(where: { $0.calendarIdentifier == listID }) {
            reminder.calendar = list
        }
        reminder.url = noteID.flatMap { InkPadLink.noteID($0) }
        if center.save(reminder) { dismiss() }
    }
}

/// Opens the editor for a new reminder about a note (from its menu, or from
/// writing circled with the lasso).
struct NoteReminderRequest: Identifiable {
    let id = UUID()
    let noteID: UUID
    var title: String

    @MainActor
    func draft() -> ReminderDraft {
        let reminder = ReminderCenter.shared.newReminder()
        reminder.title = title
        reminder.url = InkPadLink.noteID(noteID)
        return ReminderDraft(reminder: reminder, isNew: true)
    }
}
