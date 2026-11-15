import AppIntents
import UIKit

/// A note, as Siri and Shortcuts see it.
struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static let defaultQuery = NoteEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

/// Finds notes by name for the Shortcuts picker, with the library's own notes.
struct NoteEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        await MainActor.run {
            (LibraryStore.active?.notes ?? [])
                .filter { identifiers.contains($0.id) }
                .map { NoteEntity(id: $0.id, title: $0.title) }
        }
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        await MainActor.run {
            let key = NoteLinks.key(string)
            return (LibraryStore.active?.notes ?? [])
                .filter { NoteLinks.key($0.title).contains(key) || key.isEmpty }
                .prefix(20)
                .map { NoteEntity(id: $0.id, title: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        await MainActor.run {
            (LibraryStore.active?.notes ?? [])
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(20)
                .map { NoteEntity(id: $0.id, title: $0.title) }
        }
    }

    func defaultResult() async throws -> NoteEntity? {
        await MainActor.run {
            LibraryStore.active?.notes
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .first
                .map { NoteEntity(id: $0.id, title: $0.title) }
        }
    }
}

/// Creates a text note (Siri: "New note in InkPad").
struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Creates a text note with a title.")

    @Parameter(title: "Title", default: "")
    var title: String

    @Parameter(title: "Text", default: "")
    var text: String

    static var parameterSummary: any ParameterSummary {
        Summary("Create \(\.$title) with \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = LibraryStore.active else {
            return .result(dialog: IntentDialog("\(tr("Open InkPad first."))"))
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = store.createTextNote(
            titled: name.isEmpty ? tr("Untitled") : name,
            in: nil,
            extraText: body
        )
        guard let note else {
            return .result(dialog: IntentDialog("\(tr("Could not create the note."))"))
        }
        return .result(dialog: IntentDialog("\(trMessage("Created \"\(note.title)\"."))"))
    }
}

/// Adds text at the end of a note (Siri: "Add to my note in InkPad").
struct AppendNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Note"
    static let description = IntentDescription("Adds text to the end of a note.")

    @Parameter(title: "Note")
    var target: NoteEntity

    @Parameter(title: "Text", requestValueDialog: IntentDialog("What should I add?"))
    var text: String

    static var parameterSummary: any ParameterSummary {
        Summary("Add \(\.$text) to \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = LibraryStore.active else {
            return .result(dialog: IntentDialog("\(tr("Open InkPad first."))"))
        }
        guard await store.appendText(text, to: target.id) else {
            if SyncEngine.shared.openNotes.contains(target.id) {
                return .result(dialog: IntentDialog("\(trMessage("Close \"\(target.title)\" in InkPad first, then try again."))"))
            }
            return .result(dialog: IntentDialog("\(tr("Could not add to the note."))"))
        }
        return .result(dialog: IntentDialog("\(trMessage("Added to \"\(target.title)\"."))"))
    }
}

/// Opens a note in InkPad (Siri: "Open my note in InkPad").
struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens a note in InkPad.")

    @Parameter(title: "Note")
    var target: NoteEntity

    static var parameterSummary: any ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = InkPadLink.noteID(target.id) else { return .result() }
        await UIApplication.shared.open(url)
        return .result()
    }
}

/// The phrases Siri answers to.
struct InkPadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "New \(.applicationName)",
                "Create a \(.applicationName) note",
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AppendNoteIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add to my \(.applicationName) note",
            ],
            shortTitle: "Add to Note",
            systemImageName: "square.and.pencil.on.square"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: [
                "Open \(.applicationName) note",
                "Show my \(.applicationName) note",
            ],
            shortTitle: "Open Note",
            systemImageName: "doc.text"
        )
    }
}
