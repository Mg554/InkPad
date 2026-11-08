import SwiftUI

/// Builds the palette's list for what has been typed.
@MainActor
struct CommandCatalog {
    let store: LibraryStore
    let workspace: WorkspaceStore
    let center: CommandCenter
    /// Fills the search field (for "Reminder…" and similar).
    let fill: (String) -> Void

    func items(for query: String, aiItems: [PaletteItem]) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixed = noteItems() + createItems() + goToItems() + settingsItems()
        guard !trimmed.isEmpty else {
            let recent = center.recent.compactMap { id in fixed.first { $0.id == id } }
            let recentItems = recent.map { item in
                PaletteItem(id: item.id, title: item.title, subtitle: "Recent", systemImage: item.systemImage, tint: item.tint,
                            shortcut: item.shortcut, section: .suggested, keywords: item.keywords, closesPalette: item.closesPalette, run: item.run)
            }
            let rest = fixed.filter { item in !recent.contains { $0.id == item.id } && item.section != .settings }
            return recentItems + rest
        }

        var results: [PaletteItem] = []
        for intent in CommandParser.parse(trimmed) {
            let look = CommandCenter.describe(intent, money: workspace.money)
            results.append(PaletteItem(id: "intent-\(look.title)", title: look.title, subtitle: look.subtitle, systemImage: look.systemImage,
                                       tint: look.tint, shortcut: "↩", section: .suggested) { [store, workspace, center] in
                center.perform(intent, store: store, workspace: workspace)
            })
        }
        let scored = fixed
            .map { ($0, Self.score($0, query: trimmed)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        results += scored
        results += noteMatches(trimmed)
        results += aiItems
        return results
    }

    // MARK: Sections

    private func noteItems() -> [PaletteItem] {
        guard let current = center.noteCommands, let note = store.note(current.noteID) else { return [] }
        var items = current.items
        items.append(PaletteItem(id: "note-remind", title: "Remind Me About This Note…", systemImage: "bell", tint: .orange,
                                 section: .thisNote, keywords: ["reminder", "تذكير", "ذكرني"]) { [center] in
            center.sheet = .reminder(NoteReminderRequest(noteID: note.id, title: note.title).draft())
        })
        items.append(PaletteItem(id: "note-history", title: "Earlier Versions…", systemImage: "clock.arrow.circlepath", tint: .indigo,
                                 section: .thisNote, keywords: ["history", "versions", "نسخ", "سابقة"]) { [center] in
            center.sheet = .history(note)
        })
        return items
    }

    private func createItems() -> [PaletteItem] {
        [
            PaletteItem(id: "new-note", title: "New Note", systemImage: "square.and.pencil", tint: .purple, shortcut: "⌘N",
                        section: .create, keywords: ["handwritten", "ملاحظة", "جديدة"]) { [store, workspace, center] in
                center.perform(.note(title: ""), store: store, workspace: workspace)
            },
            PaletteItem(id: "new-text-note", title: "New Text Note", systemImage: "doc.text", tint: .purple, shortcut: "⌘⇧N",
                        section: .create, keywords: ["markdown", "نصية"]) { [store, workspace, center] in
                center.perform(.textNote(title: ""), store: store, workspace: workspace)
            },
            PaletteItem(id: "today-note", title: "Today's Note", systemImage: "calendar", tint: .purple, section: .create,
                        keywords: ["daily", "اليوم", "يومية"]) { [store, workspace, center] in
                let today = workspace.tasks
                    .filter { $0.status != .done && ($0.dueDate.map(Calendar.current.isDateInToday) ?? false) }
                    .map(\.title)
                if let note = store.dailyNote(tasks: today) { center.openNote(note.id) }
            },
            fillItem("new-reminder", "Reminder…", "bell.badge", .orange, "⌘⇧R", "remind me ", ["تذكير", "ذكرني"]),
            fillItem("new-task", "Task…", "checklist", .blue, "⌘⇧T", "task ", ["مهمة", "todo"]),
            fillItem("new-expense", "Expense…", "creditcard", .red, "⌘⇧E", "spent ", ["مصروف", "صرفت", "money"]),
            fillItem("new-map", "Mind Map…", "point.3.connected.trianglepath.dotted", .pink, "⌘⇧M", "mind map ", ["خريطة"]),
        ]
    }

    private func fillItem(_ id: String, _ title: String, _ image: String, _ tint: Color, _ shortcut: String, _ text: String, _ keywords: [String]) -> PaletteItem {
        PaletteItem(id: id, title: title, subtitle: "Type the rest, like \"\(text)…\"", systemImage: image, tint: tint, shortcut: shortcut,
                    section: .create, keywords: keywords, closesPalette: false) { [fill] in fill(text) }
    }

    private func goToItems() -> [PaletteItem] {
        let sections: [(String, String, String, LibraryScope, String?, [String])] = [
            ("go-all", "All Notes", "tray.full", .allNotes, "⌘1", ["library", "كل الملاحظات", "المكتبة"]),
            ("go-reminders", "Reminders", "list.bullet.circle", .reminders, "⌘2", ["التذكيرات"]),
            ("go-planner", "Planner", "checklist", .planner, "⌘3", ["tasks", "المهام", "المخطط"]),
            ("go-expenses", "Expenses", "creditcard", .expenses, "⌘4", ["money", "budget", "المصاريف", "الميزانية"]),
            ("go-maps", "Mind Maps", "point.3.connected.trianglepath.dotted", .mindMaps, "⌘5", ["الخرائط الذهنية"]),
            ("go-study", "Study with AI", "graduationcap", .study, "⌘6", ["flashcards", "quiz", "دراسة", "بطاقات"]),
            ("go-graph", "Graph", "circle.hexagongrid", .graph, "⌘7", ["links", "الشبكة"]),
            ("go-flow", "Flowmodoro", "timer", .flowmodoro, "⌘8", ["focus", "pomodoro", "تركيز", "مؤقت"]),
            ("go-slides", "Slides", "rectangle.on.rectangle.angled", .slides, nil, ["presentation", "شرائح", "عرض"]),
            ("go-unfiled", "Unfiled", "tray", .unfiled, nil, ["غير مصنفة"]),
            ("go-pdf", "PDF Tools", "doc.on.doc", .pdfTools, nil, ["merge", "split", "pdf24", "دمج", "تقسيم", "ادوات"]),
        ]
        var items = sections.map { id, title, image, scope, shortcut, keywords in
            PaletteItem(id: id, title: title, systemImage: image, shortcut: shortcut, section: .goTo, keywords: keywords) { [center] in
                center.navigate(scope)
            }
        }
        for folder in store.folders {
            items.append(PaletteItem(id: "folder-\(folder.id)", title: folder.name, subtitle: "Folder", systemImage: "folder",
                                     tint: folder.color?.color ?? .inkAccent, section: .goTo, keywords: ["folder", "مجلد"]) { [center] in
                center.navigate(.folder(folder.id))
            })
        }
        for tag in store.allTags {
            items.append(PaletteItem(id: "tag-\(tag)", title: "#\(tag)", subtitle: "Tag", systemImage: "number", tint: .teal,
                                     section: .goTo, keywords: ["tag", "وسم"]) { [center] in
                center.navigate(.tag(tag))
            })
        }
        return items
    }

    private func settingsItems() -> [PaletteItem] {
        var items: [PaletteItem] = [
            PaletteItem(id: "set-themes", title: "Themes & Theme Mixer…", systemImage: "paintbrush", section: .settings,
                        keywords: ["theme", "colors", "ثيم", "ألوان"]) { [center] in center.sheet = .themes },
            PaletteItem(id: "set-backup", title: "Back Up Now", subtitle: "Saved in InkPad Automatic Backups", systemImage: "externaldrive.badge.checkmark",
                        shortcut: "⌘⇧B", section: .settings, keywords: ["backup", "نسخة احتياطية"]) { [store, center] in
                Task {
                    let done = await store.makeAutomaticBackupIfDue(force: true)
                    center.say(done ? "Backed up to InkPad Automatic Backups" : "The backup couldn't be made")
                }
            },
            PaletteItem(id: "set-flow", title: "Start Focusing (Flowmodoro)", systemImage: "play.circle", tint: .green, section: .settings,
                        keywords: ["focus", "timer", "pomodoro", "تركيز", "ابدأ"]) { [workspace, center] in
                center.navigate(.flowmodoro)
                if let task = workspace.flowTasks.first(where: { !$0.isDone }) {
                    workspace.startFlowWork(on: task.id)
                    center.say("Focusing on \"\(task.title)\"")
                }
            },
        ]
        for appearance in AppAppearance.allCases {
            items.append(PaletteItem(id: "set-appearance-\(appearance.rawValue)", title: "Appearance: \(appearance.title)",
                                     systemImage: appearance == .dark ? "moon" : appearance == .light ? "sun.max" : "circle.lefthalf.filled",
                                     shortcut: appearance == .dark ? "⌘⇧D" : nil, section: .settings,
                                     keywords: ["dark", "light", "mode", "داكن", "فاتح", "الوضع"]) {
                UserDefaults.standard.set(appearance.rawValue, forKey: AppAppearance.storageKey)
            })
        }
        for preset in ThemePreset.all {
            items.append(PaletteItem(id: "theme-\(preset.id)", title: "Theme: \(preset.name)", systemImage: preset.season == .none ? "paintpalette" : preset.season.systemImage,
                                     tint: preset.accent, section: .settings, keywords: ["theme", "ثيم"]) {
                var recipe = ThemeRecipe.preset(preset)
                let current = ThemeSettings.current
                recipe.appFont = current.appFont
                recipe.typingFont = current.typingFont
                recipe.typingSize = current.typingSize
                recipe.cardSize = current.cardSize
                recipe.animateSeason = current.animateSeason
                recipe.glassCards = current.glassCards
                // After the palette has closed, since the app rebuilds.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ThemeSettings.shared.apply(recipe) }
            })
        }
        let handwriting = HandwritingSettingsStore.shared
        items.append(PaletteItem(id: "set-smooth", title: handwriting.settings.smooths ? "Turn Off Smooth Strokes" : "Turn On Smooth Strokes",
                                 systemImage: "scribble.variable", section: .settings, keywords: ["refine", "handwriting", "تحسين الخط"]) {
            handwriting.settings.smooths.toggle()
        })
        items.append(PaletteItem(id: "set-straighten", title: handwriting.settings.straightens ? "Turn Off Straighten Lines" : "Turn On Straighten Lines",
                                 systemImage: "text.alignleft", section: .settings, keywords: ["refine", "handwriting", "تسوية"]) {
            handwriting.settings.straightens.toggle()
        })
        let floating = UserDefaults.standard.object(forKey: CommandButtonSettings.showsKey) as? Bool ?? true
        items.append(PaletteItem(id: "set-floating", title: floating ? "Hide the Floating ⌘ Button" : "Show the Floating ⌘ Button",
                                 systemImage: "command.circle", section: .settings, keywords: ["button", "زر"]) {
            UserDefaults.standard.set(!floating, forKey: CommandButtonSettings.showsKey)
        })
        return items
    }

    private func noteMatches(_ query: String) -> [PaletteItem] {
        guard query.count >= 2 else { return [] }
        let found = store.notes
            .filter { store.matches($0, search: query) }
            .sorted { lhs, rhs in
                let a = lhs.title.localizedCaseInsensitiveContains(query)
                let b = rhs.title.localizedCaseInsensitiveContains(query)
                return a != b ? a : lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(8)
        return found.map { note in
            PaletteItem(id: "open-\(note.id)", title: note.title, subtitle: snippet(note, query: query),
                        systemImage: note.isText ? "doc.text" : "pencil.and.scribble", tint: .purple, section: .notes) { [center] in
                center.openNote(note.id)
            }
        }
    }

    /// Where the words were found, for the row's second line.
    private func snippet(_ note: NoteSummary, query: String) -> String {
        let text = store.textIndex[note.id]?.text ?? store.recognizedText[note.id] ?? ""
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return note.modifiedAt.formatted(date: .abbreviated, time: .omitted)
        }
        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
        let before: String = start > text.startIndex ? "…" : ""
        let after: String = end < text.endIndex ? "…" : ""
        let middle: String = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return before + middle + after
    }

    /// Higher is a better match: whole title, start of a word, or inside.
    static func score(_ item: PaletteItem, query: String) -> Int {
        let q = CommandParser.normalized(query)
        let words = [item.title] + item.keywords
        var best = 0
        for (index, word) in words.enumerated() {
            let w = CommandParser.normalized(word)
            let bonus = index == 0 ? 10 : 0
            if w == q { best = max(best, 100 + bonus) }
            else if w.hasPrefix(q) { best = max(best, 80 + bonus) }
            else if w.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { best = max(best, 60 + bonus) }
            else if w.contains(q) { best = max(best, 40 + bonus) }
        }
        return best
    }
}

/// Asks the AI what a sentence the iPad couldn't read means. Only the
/// sentence is sent, never notes.
enum CommandAI {
    enum Answer {
        case intent(CommandIntent)
        case open(LibraryScope)
        case search(String)
    }

    static func interpret(_ text: String, client: AIClient) async throws -> Answer {
        let now = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.colon))
        let prompt = [
            "Today is \(Date().formatted(date: .complete, time: .omitted)); now is \(now) local time.",
            "Turn this command for a note-taking app into JSON. The command may be in Arabic or English:",
            text,
            "Reply with JSON only, one of:",
            #"{"action":"reminder","title":"…","date":"YYYY-MM-DDTHH:MM","has_time":true}"#,
            #"{"action":"task","title":"…","date":"YYYY-MM-DD or null"}"#,
            #"{"action":"expense" or "income","title":"…","amount":12.5,"category":"food|transport|shopping|bills|health|education|entertainment|salary|other"}"#,
            #"{"action":"note" or "text_note" or "mind_map","title":"…"}"#,
            #"{"action":"open","section":"notes|reminders|planner|expenses|mind_maps|study|graph|flowmodoro|slides"}"#,
            #"{"action":"search","query":"…"}"#,
            "Keep titles in the command's language.",
        ].joined(separator: "\n")
        let reply = try await client.complete(system: "You turn short commands into JSON for an app. Reply with JSON only.", messages: [AIMessage(.user, prompt)])
        guard let json = AIJSON.object(in: reply), let action = json["action"] as? String else { throw AIError.unreadable }
        let title = (json["title"] as? String) ?? ""
        let date = (json["date"] as? String).flatMap(parseDate)
        switch action {
        case "reminder":
            return .intent(.reminder(title: title, due: date, hasTime: (json["has_time"] as? Bool) ?? false))
        case "task":
            return .intent(.task(title: title, due: date))
        case "expense", "income":
            let amount = (json["amount"] as? NSNumber).map { Decimal($0.doubleValue) } ?? Decimal(string: "\(json["amount"] ?? "")") ?? 0
            let category = Expense.Category(rawValue: (json["category"] as? String) ?? "") ?? (action == "income" ? .salary : .other)
            return .intent(.expense(title: title, amount: amount, category: category, isIncome: action == "income"))
        case "note": return .intent(.note(title: title))
        case "text_note": return .intent(.textNote(title: title))
        case "mind_map": return .intent(.mindMap(title: title))
        case "open":
            let sections: [String: LibraryScope] = ["notes": .allNotes, "reminders": .reminders, "planner": .planner, "expenses": .expenses,
                                                    "mind_maps": .mindMaps, "study": .study, "graph": .graph, "flowmodoro": .flowmodoro, "slides": .slides]
            guard let scope = sections[(json["section"] as? String) ?? ""] else { throw AIError.unreadable }
            return .open(scope)
        case "search":
            return .search((json["query"] as? String) ?? text)
        default:
            throw AIError.unreadable
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
