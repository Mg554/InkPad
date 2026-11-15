import Foundation

/// The services InkPad can open from inside a note: mail, calendars, and
/// the tools people keep their work in. Each plugin is a link into the
/// service on this iPad — InkPad does not keep anyone's mail or calendar
/// itself.
enum PluginCategory: String, CaseIterable, Identifiable {
    case mail, calendar, tasks, notes, other

    var id: Self { self }

    var title: String {
        switch self {
        case .mail: "Mail"
        case .calendar: "Calendars"
        case .tasks: "Tasks"
        case .notes: "Notes"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .mail: "envelope"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .notes: "note.text"
        case .other: "square.grid.2x2"
        }
    }
}

/// One service InkPad can reach.
struct Plugin: Identifiable {
    /// A link inside the service: compose mail, open a calendar, and so on.
    struct Link: Identifiable {
        let id: String
        let title: String
        let url: URL
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let category: PluginCategory
    let links: [Link]
    /// Whether InkPad suggests it to the owner.
    var isSuggested: Bool { false }

    /// The service's own app when it is on the iPad, and its website
    /// otherwise — so the link always leads somewhere.
    static func links(_ id: String, _ pairs: [(String, String)]) -> [Link] {
        pairs.compactMap { title, address in
            guard let url = URL(string: address) else { return nil }
            return Link(id: "\(id)-\(title)", title: title, url: url)
        }
    }
}

/// The plugins InkPad knows about.
enum PluginCatalog {
    static let all: [Plugin] = mail + calendars + tasks + notes + other

    static let mail: [Plugin] = [
        Plugin(
            id: "apple-mail",
            title: "Apple Mail",
            subtitle: "Write an email with Mail",
            symbol: "envelope.fill",
            category: .mail,
            links: Plugin.links("apple-mail", [("New Email", "mailto:")])
        ),
        Plugin(
            id: "gmail",
            title: "Gmail",
            subtitle: "Open Gmail, or write in the browser",
            symbol: "envelope.badge",
            category: .mail,
            links: Plugin.links("gmail", [
                ("Open Gmail", "googlemail://"),
                ("Write in Gmail", "https://mail.google.com/mail/u/0/#compose"),
            ])
        ),
        Plugin(
            id: "outlook-mail",
            title: "Outlook Mail",
            subtitle: "Outlook and Outlook.com",
            symbol: "envelope.open",
            category: .mail,
            links: Plugin.links("outlook-mail", [
                ("Open Outlook", "ms-outlook://"),
                ("Write on Outlook.com", "https://outlook.office.com/mail/deeplink/compose"),
            ])
        ),
        Plugin(
            id: "fastmail",
            title: "Fastmail",
            subtitle: "Your Fastmail account",
            symbol: "envelope.badge.shield.half.filled",
            category: .mail,
            links: Plugin.links("fastmail", [("Open Fastmail", "fastmail://")])
        ),
        Plugin(
            id: "yahoo-mail",
            title: "Yahoo Mail",
            subtitle: "Yahoo Mail in the browser",
            symbol: "envelope.badge.person.crop",
            category: .mail,
            links: Plugin.links("yahoo-mail", [("Open Yahoo Mail", "https://mail.yahoo.com")])
        ),
    ]

    static let calendars: [Plugin] = [
        Plugin(
            id: "apple-calendar",
            title: "Calendar",
            subtitle: "Your Apple calendars and events",
            symbol: "calendar",
            category: .calendar,
            links: Plugin.links("apple-calendar", [
                ("Open Calendar", "calshow://"),
                ("New Event", "x-apple-calendarkit://"),
            ])
        ),
        Plugin(
            id: "google-calendar",
            title: "Google Calendar",
            subtitle: "Events and calendars from Google",
            symbol: "calendar.badge.clock",
            category: .calendar,
            links: Plugin.links("google-calendar", [("Open Google Calendar", "https://calendar.google.com")])
        ),
        Plugin(
            id: "outlook-calendar",
            title: "Outlook Calendar",
            subtitle: "Outlook and Outlook.com events",
            symbol: "calendar.badge.exclamationmark",
            category: .calendar,
            links: Plugin.links("outlook-calendar", [
                ("Open Outlook Calendar", "ms-outlook://"),
                ("New Event on Outlook.com", "https://outlook.office.com/calendar/deeplink/compose"),
            ])
        ),
        Plugin(
            id: "fantastical",
            title: "Fantastical",
            subtitle: "Your Fantastical calendars",
            symbol: "calendar.badge.checkmark",
            category: .calendar,
            links: Plugin.links("fantastical", [("Open Fantastical", "fantastical://")])
        ),
    ]

    static let tasks: [Plugin] = [
        Plugin(
            id: "things",
            title: "Things 3",
            subtitle: "Send what you wrote to Things",
            symbol: "checkmark.circle.fill",
            category: .tasks,
            links: Plugin.links("things", [("Open Things", "things://")])
        ),
        Plugin(
            id: "todoist",
            title: "Todoist",
            subtitle: "Your Todoist projects",
            symbol: "checkmark.circle",
            category: .tasks,
            links: Plugin.links("todoist", [("Open Todoist", "todoist://")])
        ),
        Plugin(
            id: "ticktick",
            title: "TickTick",
            subtitle: "Tasks and habits",
            symbol: "checklist",
            category: .tasks,
            links: Plugin.links("ticktick", [("Open TickTick", "ticktick://")])
        ),
        Plugin(
            id: "trello",
            title: "Trello",
            subtitle: "Boards and lists",
            symbol: "rectangle.split.3x1",
            category: .tasks,
            links: Plugin.links("trello", [("Open Trello", "trello://")])
        ),
        Plugin(
            id: "reminders",
            title: "Reminders",
            subtitle: "Your Apple reminders",
            symbol: "list.bullet.circle.fill",
            category: .tasks,
            links: Plugin.links("reminders", [("Open Reminders", "x-apple-reminderkit://")])
        ),
    ]

    static let notes: [Plugin] = [
        Plugin(
            id: "obsidian",
            title: "Obsidian",
            subtitle: "Your vault of notes",
            symbol: "diamond.fill",
            category: .notes,
            links: Plugin.links("obsidian", [("Open Obsidian", "obsidian://")])
        ),
        Plugin(
            id: "notion",
            title: "Notion",
            subtitle: "Pages and databases",
            symbol: "square.stack.3d.up.fill",
            category: .notes,
            links: Plugin.links("notion", [("Open Notion", "notion://")])
        ),
        Plugin(
            id: "bear",
            title: "Bear",
            subtitle: "Markdown notes",
            symbol: "bear.fill",
            category: .notes,
            links: Plugin.links("bear", [("Open Bear", "bear://")])
        ),
        Plugin(
            id: "ulysses",
            title: "Ulysses",
            subtitle: "Long-form writing",
            symbol: "book.closed.fill",
            category: .notes,
            links: Plugin.links("ulysses", [("Open Ulysses", "ulysses://")])
        ),
        Plugin(
            id: "evernote",
            title: "Evernote",
            subtitle: "Your notebooks",
            symbol: "note.text",
            category: .notes,
            links: Plugin.links("evernote", [("Open Evernote", "evernote://")])
        ),
    ]

    static let other: [Plugin] = [
        Plugin(
            id: "dropbox",
            title: "Dropbox",
            subtitle: "Your files",
            symbol: "shippingbox.fill",
            category: .other,
            links: Plugin.links("dropbox", [("Open Dropbox", "dropbox://")])
        ),
        Plugin(
            id: "slack",
            title: "Slack",
            subtitle: "Talk about the note",
            symbol: "number",
            category: .other,
            links: Plugin.links("slack", [("Open Slack", "slack://")])
        ),
        Plugin(
            id: "whatsapp",
            title: "WhatsApp",
            subtitle: "Share what you wrote",
            symbol: "message.fill",
            category: .other,
            links: Plugin.links("whatsapp", [("Open WhatsApp", "whatsapp://")])
        ),
        Plugin(
            id: "zoom",
            title: "Zoom",
            subtitle: "Start or join a meeting",
            symbol: "video.fill",
            category: .other,
            links: Plugin.links("zoom", [("Open Zoom", "zoom://")])
        ),
        Plugin(
            id: "google-drive",
            title: "Google Drive",
            subtitle: "Your Drive files",
            symbol: "triangle.fill",
            category: .other,
            links: Plugin.links("google-drive", [("Open Google Drive", "googledrive://")])
        ),
    ]
}
