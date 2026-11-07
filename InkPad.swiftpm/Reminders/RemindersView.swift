import EventKit
import SwiftUI

/// Reminders, like Apple's app: smart lists (Today, Scheduled, All,
/// Priority, Completed) and your lists, all kept in Apple Reminders.
struct RemindersView: View {
    @ObservedObject private var center = ReminderCenter.shared
    @State private var newListName: NamePrompt?
    @State private var listToDelete: EKCalendar?

    var body: some View {
        Group {
            switch center.access {
            case .granted:
                home
            case .unknown:
                ContentUnavailableView {
                    Label("Reminders", systemImage: "list.bullet.circle")
                } description: {
                    Text("See and edit your Reminders here, and link them to notes. They stay in Apple's Reminders app, which sends their alerts.")
                } actions: {
                    Button("Allow Access to Reminders") {
                        Task { await center.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .denied:
                ContentUnavailableView(
                    "No Access to Reminders",
                    systemImage: "lock",
                    description: Text("Allow InkPad in Settings › Privacy & Security › Reminders (Full Access).")
                )
            }
        }
        .navigationTitle("Reminders")
        .task { await center.refresh() }
        .alert("Reminders", isPresented: Binding(get: { center.errorMessage != nil }, set: { if !$0 { center.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(center.errorMessage ?? "")
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(ReminderCenter.SmartList.allCases) { smart in
                        NavigationLink {
                            ReminderListView(source: .smart(smart))
                        } label: {
                            smartTile(smart)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                HStack {
                    Text("My Lists")
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        newListName = NamePrompt(title: "New List", initialText: "", confirmTitle: "Add") {
                            center.addList(named: $0, color: .blue)
                        }
                    } label: {
                        Label("Add List", systemImage: "plus")
                    }
                }
                VStack(spacing: 0) {
                    ForEach(center.lists, id: \.calendarIdentifier) { list in
                        NavigationLink {
                            ReminderListView(source: .list(list))
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "list.bullet.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color(cgColor: list.cgColor))
                                Text(list.title)
                                    .foregroundStyle(Color(uiColor: .label))
                                Spacer()
                                Text("\(center.reminders(in: list).count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if list.allowsContentModifications {
                                Button(role: .destructive) {
                                    listToDelete = list
                                } label: {
                                    Label("Delete List", systemImage: "trash")
                                }
                            }
                        }
                        Divider().padding(.leading, 60)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .namePrompt($newListName)
        .confirmationDialog(
            "Delete the list \"\(listToDelete?.title ?? "")\" and its reminders?",
            isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
            titleVisibility: .visible,
            presenting: listToDelete
        ) { list in
            Button("Delete List", role: .destructive) { center.deleteList(list) }
        } message: { _ in
            Text("It is also deleted from the Reminders app.")
        }
    }

    private func smartTile(_ smart: ReminderCenter.SmartList) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: smart.systemImage)
                    .font(.title)
                    .foregroundStyle(smart.tint)
                Spacer()
                Text(smart == .completed ? "" : "\(center.reminders(in: smart).count)")
                    .font(.title.bold())
                    .foregroundStyle(Color(uiColor: .label))
            }
            Text(smart.title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// One smart list or list of reminders, with quick add at the bottom.
struct ReminderListView: View {
    enum Source {
        case smart(ReminderCenter.SmartList)
        case list(EKCalendar)
    }

    @EnvironmentObject private var store: LibraryStore
    @Environment(\.noteNavigation) private var navigation
    @ObservedObject private var center = ReminderCenter.shared
    let source: Source

    @State private var newTitle = ""
    @State private var editing: ReminderDraft?
    @FocusState private var isAdding: Bool

    private var title: String {
        switch source {
        case let .smart(smart): smart.title
        case let .list(list): list.title
        }
    }

    private var tint: Color {
        switch source {
        case let .smart(smart): smart.tint
        case let .list(list): Color(cgColor: list.cgColor)
        }
    }

    private var reminders: [EKReminder] {
        switch source {
        case let .smart(smart): center.reminders(in: smart)
        case let .list(list): center.reminders(in: list)
        }
    }

    private var canAdd: Bool {
        if case .smart(.completed) = source { return false }
        return true
    }

    var body: some View {
        List {
            ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                ReminderRow(reminder: reminder) {
                    editing = ReminderDraft(reminder: reminder)
                } openNote: { id in
                    navigation.openNote(id)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        center.delete(reminder)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if canAdd {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                    TextField("New Reminder", text: $newTitle)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit(addQuickly)
                }
            }
            if reminders.isEmpty && !canAdd {
                Text("Nothing completed in the last 30 days.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if canAdd {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = ReminderDraft(reminder: newReminder(), isNew: true)
                    } label: {
                        Label("New Reminder", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing) { draft in
            ReminderEditor(draft: draft)
                .environmentObject(store)
        }
        .refreshable { await center.refresh() }
    }

    private func newReminder() -> EKReminder {
        var list: EKCalendar?
        if case let .list(chosen) = source { list = chosen }
        let reminder = center.newReminder(in: list)
        if case .smart(.today) = source { reminder.setDue(Date(), hasTime: false) }
        if case .smart(.priority) = source { reminder.priority = 1 }
        return reminder
    }

    private func addQuickly() {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let reminder = newReminder()
        reminder.title = newTitle
        center.save(reminder)
        newTitle = ""
        isAdding = true
    }
}

/// A reminder: tap the circle to complete it, tap the row to edit it.
struct ReminderRow: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var center = ReminderCenter.shared
    let reminder: EKReminder
    let edit: () -> Void
    let openNote: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation { center.toggle(reminder) }
            } label: {
                Image(systemName: reminder.isCompleted ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isCompleted ? reminder.listColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.isCompleted ? "Mark as Not Done" : "Mark as Done")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if !reminder.priorityMarks.isEmpty {
                        Text(reminder.priorityMarks)
                            .foregroundStyle(reminder.listColor)
                            .bold()
                    }
                    Text(reminder.title ?? "")
                        .strikethrough(reminder.isCompleted)
                        .foregroundStyle(reminder.isCompleted ? Color.secondary : Color(uiColor: .label))
                }
                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let due = reminder.dueDate {
                        Label(Self.dueText(due, hasTime: reminder.hasDueTime), systemImage: "calendar")
                            .foregroundStyle(reminder.isOverdue ? Color.red : Color.secondary)
                    }
                    if let id = reminder.linkedNoteID, let note = store.note(id) {
                        Button {
                            openNote(id)
                        } label: {
                            Label(note.title, systemImage: "doc.text")
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(reminder.calendar?.title ?? "")
                        .foregroundStyle(reminder.listColor)
                }
                .font(.caption)
            }
            Spacer()
            Button(action: edit) {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Details")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
    }

    static func dueText(_ date: Date, hasTime: Bool) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.day().month(.abbreviated).year())
        }
        return hasTime ? "\(day), \(date.formatted(date: .omitted, time: .shortened))" : day
    }
}
