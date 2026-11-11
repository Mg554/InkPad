import SwiftUI

enum LivingTab: String, CaseIterable, Identifiable {
    case related, concepts, links, new, study
    var id: Self { self }

    var title: String {
        switch self {
        case .related: "Related"
        case .concepts: "Concepts"
        case .links: "Links"
        case .new: "New"
        case .study: "Study"
        }
    }

    var systemImage: String {
        switch self {
        case .related: "point.3.filled.connected.trianglepath.dotted"
        case .concepts: "lightbulb"
        case .links: "link.badge.plus"
        case .new: "sparkle"
        case .study: "rectangle.stack"
        }
    }
}

/// The floating Living Notes bubble on a note: a count of related notes;
/// tap it for the list of what Living Notes can show.
struct LivingBubble: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var living = LivingNotes.shared
    let noteID: UUID
    var liveText: String?
    let isText: Bool
    let open: (LivingTab) -> Void
    @State private var isShowingMenu = false
    @State private var pulse = false

    var body: some View {
        let isOn = living.settings.isOn(for: noteID)
        let related = isOn ? living.related(to: noteID, liveText: liveText, store: store) : []
        let fresh = isOn ? living.newSinceLastVisit(noteID, store: store) : []
        ZStack(alignment: .topTrailing) {
                Image(systemName: isOn ? "leaf.circle.fill" : "leaf.circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white, isOn ? Color.green.gradient : Color.gray.gradient)
                    .frame(width: 50, height: 50)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: (isOn ? Color.green : .clear).opacity(pulse ? 0.7 : 0.3), radius: pulse ? 14 : 8)
                if isOn, !related.isEmpty {
                    Text("\(related.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(fresh.isEmpty ? Color.green : Color.orange, in: Capsule())
                        .offset(x: 4, y: -2)
                        .contentTransition(.numericText())
                }
        }
        // A tap, not a button, so dragging the bubble doesn't open it.
        .contentShape(Circle())
        .onTapGesture { isShowingMenu = true }
        .accessibilityLabel("Living Notes, \(related.count) related")
        .accessibilityHint("Drag to move it")
        .accessibilityAddTraits(.isButton)
        .onChange(of: related.count) {
            withAnimation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true)) { pulse.toggle() }
        }
        .popover(isPresented: $isShowingMenu) {
            menu(related: related, fresh: fresh)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func menu(related: [LivingNotes.Related], fresh: [LivingNotes.Related]) -> some View {
        let isOn = living.settings.isOn(for: noteID)
        let concepts = isOn ? living.concepts(in: noteID, liveText: liveText) : []
        let links = isOn ? living.suggestedLinks(for: noteID, store: store) : []
        let decks = isOn ? living.decks(for: noteID, workspace: workspace) : []
        return VStack(alignment: .leading, spacing: 4) {
            Label("Living Notes", systemImage: "leaf")
                .font(.headline)
                .padding(.bottom, 6)
            if isOn {
                option(.related, "Related Notes", related.count)
                option(.concepts, "Concepts in This Note", concepts.count)
                option(.links, "Suggested Links", links.count)
                option(.new, "New Since Your Last Visit", fresh.count)
                option(.study, "Flashcards & Memory", decks.count)
                Divider().padding(.vertical, 6)
                if isText {
                    Toggle("Underline Concepts", isOn: $living.settings.highlightsConcepts)
                } else {
                    Toggle("Bubbles Next to Writing", isOn: $living.settings.inkBubbles)
                }
            }
            Toggle("Living Notes for This Note", isOn: Binding(
                get: { !living.settings.offNotes.contains(noteID.uuidString) },
                set: { on in
                    living.settings.offNotes.removeAll { $0 == noteID.uuidString }
                    if !on { living.settings.offNotes.append(noteID.uuidString) }
                }
            ))
            Toggle("Living Notes Everywhere", isOn: $living.settings.isOn)
            Text("Everything is found on this iPad. Nothing is sent anywhere unless you tap Explain the Connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding()
        .frame(width: 330)
    }

    private func option(_ tab: LivingTab, _ title: String, _ count: Int) -> some View {
        Button {
            isShowingMenu = false
            open(tab)
        } label: {
            HStack {
                Label(tr(title), systemImage: tab.systemImage)
                Spacer()
                Text("\(count)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(count > 0 ? Color.green : Color.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The side panel: related notes, concepts, suggested links, what's new
/// and flashcards for the open note.
struct LivingPanel: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @ObservedObject private var living = LivingNotes.shared
    @ObservedObject private var ai = AISettings.shared
    let noteID: UUID
    var liveText: String?
    @Binding var tab: LivingTab
    @State private var explanations: [UUID: String] = [:]
    @State private var explaining: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $tab) {
                ForEach(LivingTab.allCases) { Image(systemName: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            Text(tr(tab.title)).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .related:
            let items = living.related(to: noteID, liveText: liveText, store: store)
            if items.isEmpty { empty("No related notes yet. Keep writing: notes that share concepts appear here.") }
            ForEach(items) { relatedCard($0, suggest: false) }
        case .concepts:
            let concepts = living.concepts(in: noteID, liveText: liveText)
            if concepts.isEmpty { empty("Concepts this note shares with other notes appear here.") }
            FlowChips(items: concepts) { concept in
                CommandCenter.shared.sheet = .concept(concept.key)
            }
        case .links:
            let items = living.suggestedLinks(for: noteID, store: store)
            if items.isEmpty { empty("No links to suggest right now.") }
            ForEach(items) { relatedCard($0, suggest: true) }
        case .new:
            let items = living.newSinceLastVisit(noteID, store: store)
            if items.isEmpty {
                empty(living.lastSeen(noteID) == nil
                      ? "Next time you open this note, related notes written in the meantime show here."
                      : "Nothing new about this note's topics since your last visit.")
            }
            ForEach(items) { relatedCard($0, suggest: false) }
        case .study:
            let decks = living.decks(for: noteID, workspace: workspace)
            if decks.isEmpty { empty("Flashcards made from this note, or about its concepts, show here with how well you remember them.") }
            ForEach(decks) { deck in
                let strength = deck.memoryStrength()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr(deck.title)).font(.headline)
                        Text("\(deck.cards.count) cards · \(deck.dueCount) due").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let strength {
                        Text("\(Int(strength * 100))%")
                            .font(.title3.bold())
                            .foregroundStyle(strength < 0.6 ? Color.red : strength < 0.8 ? Color.orange : Color.green)
                    } else {
                        Text("Not studied").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .themedCard()
            }
        }
    }

    private func relatedCard(_ item: LivingNotes.Related, suggest: Bool) -> some View {
        let note = store.note(item.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: note?.isText == true ? "doc.text" : "pencil.and.scribble").foregroundStyle(.green)
                Text(note?.title ?? "Note").font(.headline).lineLimit(1)
                Spacer()
                if item.isLinked { Image(systemName: "link").foregroundStyle(.secondary) }
                Text("\(Int(item.score * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(item.shared.joined(separator: " · "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Text(item.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            if let explanation = explanations[item.id] {
                Text(explanation).font(.callout).padding(10).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("Open") { navigation.openNote(item.id) }
                    .buttonStyle(.bordered)
                if suggest {
                    Button("Link") { withAnimation { living.accept(noteID, item.id) } }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    Button("Not Related") { withAnimation { living.dismiss(noteID, item.id) } }
                        .buttonStyle(.bordered)
                } else if !item.isLinked {
                    Button("Link") { withAnimation { living.accept(noteID, item.id) } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if ai.problem == nil {
                    Button {
                        explain(item)
                    } label: {
                        if explaining == item.id { ProgressView() } else { Label("Explain", systemImage: "sparkles") }
                    }
                    .buttonStyle(.borderless)
                    .disabled(explaining != nil)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .themedCard()
    }

    private func empty(_ text: String) -> some View {
        Text(tr(text)).font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
    }

    /// Asks the AI how the two notes connect, if the AI Firewall allows both.
    private func explain(_ item: LivingNotes.Related) {
        guard let client = ai.client() else { return }
        let onDevice = client.kind.isOnDevice
        guard store.mayUseAI(noteID, onDevice: onDevice), store.mayUseAI(item.id, onDevice: onDevice) else {
            explanations[item.id] = NoteTexts.firewallMessage(onDevice: onDevice)
            return
        }
        let a = (store.note(noteID)?.title ?? "") + "\n" + living.snippet(in: noteID, around: item.shared.first ?? "", length: 1200)
        let b = (store.note(item.id)?.title ?? "") + "\n" + living.snippet(in: item.id, around: item.shared.first ?? "", length: 1200)
        explaining = item.id
        Task {
            defer { explaining = nil }
            do {
                let reply = try await client.complete(
                    system: "You help a student connect their notes. Answer in the notes' language, in 2–3 short sentences.",
                    messages: [AIMessage(.user, "How do these two notes connect, and what should I remember about the link? They share: \(item.shared.joined(separator: ", ")).\n\nNote A:\n\(a)\n\nNote B:\n\(b)")]
                )
                explanations[item.id] = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                explanations[item.id] = "Couldn't explain: \(error.localizedDescription)"
            }
        }
    }
}

/// Concept chips that wrap onto new lines.
private struct FlowChips: View {
    let items: [LivingNotes.Concept]
    let tap: (LivingNotes.Concept) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { concept in
                Button {
                    tap(concept)
                } label: {
                    HStack(spacing: 4) {
                        Text(concept.display).lineLimit(1)
                        Text("\(concept.otherNotes)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).background(Color.green, in: Capsule())
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Everything written about one concept, across notes, oldest first.
struct ConceptCardView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var living = LivingNotes.shared
    let key: String

    var body: some View {
        let mentions = living.mentions(of: key, store: store)
        let name = living.display(of: key)
        let cards = workspace.flashcardDecks.flatMap { deck in
            deck.cards.filter { $0.front.localizedCaseInsensitiveContains(name) || $0.back.localizedCaseInsensitiveContains(name) }
                .map { (deck, $0) }
        }
        NavigationStack {
            List {
                Section {
                    ForEach(mentions) { mention in
                        Button {
                            dismiss()
                            CommandCenter.shared.openNote(mention.noteID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(tr(mention.title)).font(.headline).foregroundStyle(Color(uiColor: .label))
                                    Spacer()
                                    Text(mention.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                                }
                                Text(mention.snippet).font(.callout).foregroundStyle(Color(uiColor: .secondaryLabel))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("In \(mentions.count) notes, oldest first")
                }
                if !cards.isEmpty {
                    Section("Flashcards") {
                        ForEach(cards, id: \.1.id) { deck, card in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.front).font(.subheadline.weight(.semibold))
                                Text(card.back).font(.caption).foregroundStyle(.secondary)
                                if let recall = card.recall() {
                                    Text("Memory \(Int(recall * 100))% · \(deck.title)")
                                        .font(.caption2)
                                        .foregroundStyle(recall < 0.6 ? Color.red : Color.green)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        makeConceptNote(name: name, mentions: mentions)
                    } label: {
                        Label("Make a Concept Note", systemImage: "doc.badge.plus")
                    }
                } footer: {
                    Text("A text note that gathers these passages with [[links]] to each note.")
                }
            }
            .navigationTitle(tr(name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func makeConceptNote(name: String, mentions: [LivingNotes.Mention]) {
        let body = mentions.map { "## [[\($0.title)]]\n_\($0.date.formatted(date: .abbreviated, time: .omitted))_\n\n> \($0.snippet)" }
            .joined(separator: "\n\n")
        if let note = store.createTextNote(titled: "Concept: \(name)", in: nil, extraText: body) {
            dismiss()
            CommandCenter.shared.openNote(note.id)
        }
    }
}
