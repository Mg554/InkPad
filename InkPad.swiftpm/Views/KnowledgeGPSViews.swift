import PDFKit
import SwiftUI

// MARK: Maps list

/// Knowledge GPS: every map, and making a new one.
struct KnowledgeMapsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("A map of what you're learning: a book's chapters, a subject's notes, or stations you make (like an exam syllabus). See where you are, what's next, and whether you'll be ready by the exam.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if workspace.knowledgeMaps.isEmpty {
                    ContentUnavailableView("No Maps Yet", systemImage: "location.north.circle", description: Text("Tap + to map a book, a subject or a syllabus."))
                        .padding(.top, 30)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(workspace.knowledgeMaps) { map in
                        NavigationLink {
                            KnowledgeMapView(mapID: map.id)
                        } label: {
                            MapCard(map: map)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                workspace.deleteKnowledgeMap(map.id)
                            } label: {
                                Label("Delete Map", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .themedBackground()
        .navigationTitle("Knowledge GPS")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("New Map", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            NewKnowledgeMapSheet()
        }
    }
}

private struct MapCard: View {
    let map: KnowledgeMap

    private var sourceText: String {
        switch map.source {
        case .book: "Book · \(map.stations.count) chapters"
        case let .tag(tag): "#\(tag) · \(map.stations.count) notes"
        case .manual: "\(map.stations.count) stations"
        }
    }

    var body: some View {
        let marked = map.stations.filter { $0.mark == .mastered }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: map.style.systemImage).font(.title2).foregroundStyle(Color.inkAccent)
                Spacer()
                if let exam = map.examDate {
                    Label(exam.formatted(date: .abbreviated, time: .omitted), systemImage: "graduationcap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(tr(map.title)).font(.headline).foregroundStyle(Color(uiColor: .label)).lineLimit(2)
            Text(sourceText).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: Double(marked), total: Double(max(map.stations.count, 1)))
                .tint(.green)
            Text("\(marked) of \(map.stations.count) mastered").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }
}

// MARK: New map

private struct NewKnowledgeMapSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case book = "A Book"
        case tag = "A Subject"
        case manual = "By Hand"
        var id: Self { self }
    }

    @State private var kind = Kind.book
    @State private var bookID: UUID?
    @State private var tag: String?
    @State private var title = ""
    @State private var lines = ""
    @State private var hasExam = false
    @State private var examDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var isMaking = false
    @State private var problem: String?
    @State private var books: [NoteSummary] = []

    var body: some View {
        NavigationStack {
            Form {
                Picker("Map", selection: $kind) {
                    ForEach(Kind.allCases) { Text(tr($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                switch kind {
                case .book:
                    Section {
                        Picker("Book", selection: $bookID) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(books) { Text(tr($0.title)).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.navigationLink)
                    } footer: {
                        Text("Each chapter of the book's outline becomes a station. Reading, flashcards, quizzes and focus on it move you along.")
                    }
                case .tag:
                    Section {
                        Picker("Subject", selection: $tag) {
                            Text("Choose…").tag(String?.none)
                            ForEach(store.allTags, id: \.self) { Text("#\($0)").tag(Optional($0)) }
                        }
                        .pickerStyle(.navigationLink)
                    } footer: {
                        Text("Each note with this tag becomes a station.")
                    }
                case .manual:
                    Section {
                        TextField("Map name (e.g. NBRC TMC Exam)", text: $title)
                        TextEditor(text: $lines)
                            .frame(minHeight: 160)
                            .overlay(alignment: .topLeading) {
                                if lines.isEmpty {
                                    Text("One station per line:\nAirway management\nMechanical ventilation\nABG interpretation")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    } footer: {
                        Text("Link notes or books to stations later, from each station.")
                    }
                }
                Section {
                    Toggle("Exam Date", isOn: $hasExam)
                    if hasExam {
                        DatePicker("Date", selection: $examDate, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text("With an exam date, the GPS works out the pace you need and suggests a daily route.")
                }
                if let problem {
                    Text(trMessage(problem)).foregroundStyle(.red)
                }
            }
            .task { books = store.notes.filter { !$0.isText && store.hasPDF($0.id) } }
            .navigationTitle("New Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isMaking {
                        ProgressView()
                    } else {
                        Button("Make") { make() }.disabled(!canMake)
                    }
                }
            }
        }
    }

    private var canMake: Bool {
        switch kind {
        case .book: return bookID != nil
        case .tag: return tag != nil
        case .manual: return !title.trimmingCharacters(in: .whitespaces).isEmpty && !KnowledgeGPS.stations(fromLines: lines).isEmpty
        }
    }

    private func make() {
        switch kind {
        case .book:
            guard let bookID else { return }
            isMaking = true
            Task {
                defer { isMaking = false }
                guard let content = try? store.loadContent(for: bookID), let document = content.pdf?.pdfDocument else {
                    problem = "The book couldn't be opened."
                    return
                }
                var chapters = await Task.detached(priority: .userInitiated) { PDFToolKit.chapters(of: document, maxDepth: 0) }.value
                if chapters.isEmpty {
                    // No outline: parts of 20 pages.
                    var first = 0
                    while first < document.pageCount {
                        let last = min(first + 19, document.pageCount - 1)
                        chapters.append(BookChapter(id: "part-\(first)", title: "Pages \(first + 1)–\(last + 1)", firstPage: first, lastPage: last, depth: 0))
                        first = last + 1
                    }
                }
                let name = store.note(bookID)?.title ?? "Book"
                save(KnowledgeMap(title: name, source: .book(bookID), stations: KnowledgeGPS.stations(forBook: bookID, chapters: chapters)))
            }
        case .tag:
            guard let tag else { return }
            let notes = store.notes(in: .tag(tag))
            save(KnowledgeMap(title: "#\(tag)", source: .tag(tag), stations: KnowledgeGPS.stations(forTag: tag, notes: notes)))
        case .manual:
            save(KnowledgeMap(title: title.trimmingCharacters(in: .whitespaces), source: .manual, stations: KnowledgeGPS.stations(fromLines: lines)))
        }
    }

    private func save(_ map: KnowledgeMap) {
        var map = map
        if hasExam { map.examDate = examDate }
        workspace.save(map)
        CommandCenter.shared.say("Map ready: \(map.stations.count) stations")
        dismiss()
    }
}

// MARK: One map

/// The map with the stations, "you are here", and the route.
struct KnowledgeMapView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    let mapID: UUID

    @State private var evidence = KnowledgeEvidence()
    @State private var progress: [StationProgress] = []
    @State private var evidenceVersion = 0
    @State private var selected: KnowledgeStation?
    @State private var isEditing = false

    /// What the progress depends on, to work it out again only when it changes.
    private struct Inputs: Equatable {
        let map: KnowledgeMap?
        let sessions: Int
        let tasks: Int
        let decks: Int
        let evidence: Int
    }

    private var map: KnowledgeMap? { workspace.knowledgeMaps.first(where: { $0.id == mapID }) }

    var body: some View {
        Group {
            if let map {
                content(map)
            } else {
                ContentUnavailableView("Map Not Found", systemImage: "map")
            }
        }
        .themedBackground()
        .task(id: workspace.flowSessions.count) { await gatherEvidence() }
        .task(id: Inputs(map: map, sessions: workspace.flowSessions.count, tasks: workspace.tasks.count, decks: workspace.flashcardDecks.count, evidence: evidenceVersion)) {
            guard let map else { return }
            var made: [StationProgress] = []
            for station in map.stations {
                made.append(KnowledgeGPS.progress(of: station, in: map, evidence: evidence))
            }
            progress = made
        }
    }

    private func content(_ map: KnowledgeMap) -> some View {
        let progress: [StationProgress] = self.progress.count == map.stations.count ? self.progress : map.stations.map { _ in
            StationProgress(reading: nil, memory: nil, focusMinutes: 0, quizzes: nil, mark: .none, value: 0)
        }
        let route = KnowledgeGPS.route(for: map, progress: progress, sessions: workspace.flowSessions)
        return HStack(alignment: .top, spacing: 0) {
            ScrollView {
                KnowledgeMapCanvas(map: map, progress: progress, here: route.here, open: { selected = $0 }, go: { station in
                    if !KnowledgeGPS.go(to: station) { selected = station }
                })
                    .padding(.vertical, 20)
            }
            Divider()
            RoutePanel(map: map, progress: progress, route: route) { selected = $0 }
                .frame(width: 330)
        }
        .navigationTitle(tr(map.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Style", selection: Binding(get: { map.style }, set: { style in
                    var changed = map
                    changed.style = style
                    workspace.save(changed)
                })) {
                    ForEach(KnowledgeMap.Style.allCases) { Text(tr($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditing = true
                } label: {
                    Label("Map Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(item: $selected) { station in
            StationSheet(mapID: mapID, stationID: station.id, evidence: evidence)
        }
        .sheet(isPresented: $isEditing) {
            MapSettingsSheet(mapID: mapID)
        }
    }

    /// Reading progress from the book, flashcards, quizzes, focus and tasks.
    private func gatherEvidence() async {
        guard let map else { return }
        var found = KnowledgeEvidence()
        found.decks = workspace.flashcardDecks
        found.quizzes = workspace.quizzes
        found.sessions = workspace.flowSessions
        found.tasks = workspace.tasks
        if let book = map.bookID, let content = try? store.loadContent(for: book) {
            let pages = content.metadata.resolvedPages(pdfPageCount: content.pdf?.pageCount ?? 0)
            let furthest = max(content.metadata.furthestPage ?? 0, content.metadata.readingPage ?? 0)
            var pdfPage = -1
            for index in 0...min(furthest, max(pages.count - 1, 0)) where pages.indices.contains(index) {
                if case let .pdf(page) = pages[index] { pdfPage = max(pdfPage, page) }
            }
            // Opening the book isn't reading it: only pages turned to count.
            if furthest > 0, pdfPage >= 0 { found.furthestPDFPage[book] = pdfPage }
        }
        let monthAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        for station in map.stations {
            if let id = station.noteID, let note = store.note(id), note.modifiedAt >= monthAgo, note.modifiedAt > note.createdAt.addingTimeInterval(60) {
                found.touchedNotes.insert(id)
            }
        }
        evidence = found
        evidenceVersion += 1
    }
}

// MARK: Drawing the map

private struct KnowledgeMapCanvas: View {
    let map: KnowledgeMap
    let progress: [StationProgress]
    let here: Int?
    /// Shows the station's progress and actions.
    let open: (KnowledgeStation) -> Void
    /// Goes straight to the chapter's pages.
    let go: (KnowledgeStation) -> Void

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(style: map.style, count: map.stations.count, width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawPath(&context, points: points)
                }
                ForEach(Array(map.stations.enumerated()), id: \.element.id) { item in
                    if item.offset < points.count, item.offset < progress.count {
                        stationView(item.element, index: item.offset)
                            .position(points[item.offset])
                    }
                }
            }
        }
        .frame(height: Self.height(style: map.style, count: map.stations.count))
    }

    /// Stops per metro row: fewer when the map is narrow, so labels don't overlap.
    static func metroColumns(_ width: CGFloat) -> Int {
        width < 640 ? 3 : 4
    }

    static func height(style: KnowledgeMap.Style, count: Int) -> CGFloat {
        switch style {
        case .islands: return CGFloat(count) * 150 + 80
        case .metro: return CGFloat((count + 2) / 3) * 170 + 60
        case .tree: return CGFloat(count) * 120 + 60
        }
    }

    static func points(style: KnowledgeMap.Style, count: Int, width: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        let w = Double(max(width, 260))
        let columns = metroColumns(width)
        for index in 0..<count {
            let i = Double(index)
            switch style {
            case .islands:
                let x: Double = w / 2 + Math.sine(i * 1.15) * w * 0.27
                result.append(CGPoint(x: x, y: 90 + i * 150))
            case .metro:
                let row = index / columns
                let column = index % columns
                let forward = row % 2 == 0
                let slot: Double = Double(forward ? column : columns - 1 - column)
                // Room at both edges for the names (about 130 pt wide).
                let margin: Double = 80
                let step: Double = (w - margin * 2) / Double(max(columns - 1, 1))
                let x: Double = margin + slot * step
                result.append(CGPoint(x: x, y: 80 + Double(row) * 170))
            case .tree:
                let x: Double = index % 2 == 0 ? w * 0.36 : w * 0.64
                result.append(CGPoint(x: x, y: 70 + i * 120))
            }
        }
        return result
    }

    private func drawPath(_ context: inout GraphicsContext, points: [CGPoint]) {
        guard points.count > 1 else { return }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            switch map.style {
            case .islands:
                let bend: CGFloat = index % 2 == 0 ? 40 : -40
                let control = CGPoint(x: (from.x + to.x) / 2 + bend, y: (from.y + to.y) / 2)
                path.addQuadCurve(to: to, control: control)
            case .metro, .tree:
                path.addLine(to: to)
            }
        }
        switch map.style {
        case .islands:
            context.stroke(path, with: .color(Color(red: 0.82, green: 0.68, blue: 0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [10, 9]))
        case .metro:
            context.stroke(path, with: .color(Color.inkAccent.opacity(0.85)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        case .tree:
            context.stroke(path, with: .color(Color.green.opacity(0.5)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private func color(_ level: StationProgress.Level) -> Color {
        switch level {
        case .fog: return Color.gray
        case .started: return Color.orange
        case .understood: return Color.teal
        case .mastered: return Color.green
        }
    }

    @ViewBuilder
    private func stationView(_ station: KnowledgeStation, index: Int) -> some View {
        let state = progress[index]
        let isHere = index == here
        Button {
            go(station)
        } label: {
            switch map.style {
            case .islands: island(station, state: state, isHere: isHere)
            case .metro: metroStop(station, state: state, isHere: isHere)
            case .tree: treeNode(station, state: state, isHere: isHere, index: index)
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button {
                go(station)
            } label: {
                Label(station.firstPage == nil ? "Open" : "Open at This Chapter", systemImage: "book")
            }
            Button {
                open(station)
            } label: {
                Label("Progress & Details", systemImage: "chart.bar")
            }
        }
    }

    private func island(_ station: KnowledgeStation, state: StationProgress, isHere: Bool) -> some View {
        let tint = color(state.level)
        return VStack(spacing: 4) {
            if isHere {
                Label("You are here", systemImage: "mappin.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
            }
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [tint.opacity(0.85), Color(red: 0.93, green: 0.85, blue: 0.62)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 140, height: 70)
                    .shadow(color: tint.opacity(0.4), radius: 8)
                if state.level == .mastered {
                    Image(systemName: "flag.fill").foregroundStyle(.white).font(.title3)
                } else if state.level != .fog {
                    Text("\(Int(state.value * 100))%").font(.headline).foregroundStyle(.white)
                }
                if state.level == .fog {
                    // Fog over places not yet visited.
                    Ellipse().fill(Color.white.opacity(0.55)).frame(width: 150, height: 80).blur(radius: 6)
                    Image(systemName: "cloud.fog.fill").foregroundStyle(.gray)
                }
            }
            Text(tr(station.title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
                .frame(maxWidth: 180)
        }
    }

    private func metroStop(_ station: KnowledgeStation, state: StationProgress, isHere: Bool) -> some View {
        let tint = color(state.level)
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(state.level == .mastered ? tint : Color(uiColor: .systemBackground)).frame(width: 30, height: 30)
                Circle().stroke(tint, lineWidth: 5).frame(width: 30, height: 30)
                if isHere {
                    Circle().stroke(Color.red, lineWidth: 3).frame(width: 44, height: 44)
                }
            }
            Text(tr(station.title))
                .font(.caption.weight(isHere ? .bold : .medium))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 130)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            Text("\(Int(state.value * 100))%").font(.caption2).foregroundStyle(.secondary)
        }
        .offset(y: 26)
    }

    private func treeNode(_ station: KnowledgeStation, state: StationProgress, isHere: Bool, index: Int) -> some View {
        let tint = color(state.level)
        let locked: Bool = state.level == .fog && index > (here ?? 0) + 1
        let content = HStack(spacing: 10) {
            Image(systemName: locked ? "lock.fill" : (state.level == .mastered ? "star.fill" : "leaf.fill"))
                .foregroundStyle(locked ? Color.gray : tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(station.title)).font(.callout.weight(.semibold)).lineLimit(2).foregroundStyle(Color(uiColor: .label))
                ProgressView(value: state.value).tint(tint)
            }
        }
        // The card stays solid (lines pass behind it); only its content dims when locked.
        return content
            .opacity(locked ? 0.5 : 1)
            .padding(12)
            .frame(width: 230)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isHere ? Color.red : tint.opacity(0.5), lineWidth: isHere ? 2.5 : 1))
    }
}

// MARK: Route

private struct RoutePanel: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let map: KnowledgeMap
    let progress: [StationProgress]
    let route: KnowledgeGPS.Route
    let open: (KnowledgeStation) -> Void

    private func studyTitle(_ station: KnowledgeStation) -> String { "Study: \(station.title)" }

    var body: some View {
        List {
            Section {
                let mastered = progress.filter { $0.level == .mastered }.count
                ProgressView(value: Double(mastered), total: Double(max(progress.count, 1))) {
                    Text("\(mastered) of \(progress.count) mastered").font(.subheadline.weight(.semibold))
                }
                .tint(.green)
                if let here = route.here, here < map.stations.count {
                    stationRow("You Are Here", map.stations[here], icon: "mappin.circle.fill", tint: .red)
                }
                if let next = route.next, next < map.stations.count {
                    stationRow("Next Stop", map.stations[next], icon: "arrow.turn.up.right", tint: .blue)
                }
            }
            Section("Time Left") {
                LabeledContent("Study left", value: PlannerInsights.duration(route.minutesLeft * 60))
                LabeledContent("Your pace", value: "\(route.dailyMinutes) min a day")
                LabeledContent("Done in about", value: route.daysToFinish == 1 ? "1 day" : "\(route.daysToFinish) days")
                if route.examPassed {
                    LabeledContent("Exam", value: "Passed — set a new date in Map Settings")
                }
                if let days = route.daysToExam {
                    LabeledContent("Exam in", value: days == 0 ? "Today" : (days == 1 ? "1 day" : "\(days) days"))
                    if let needed = route.neededPerDay {
                        LabeledContent("Needed", value: "\(PlannerInsights.duration(needed * 60)) a day")
                    }
                }
            }
            if route.isBehind {
                Section {
                    Label("You're behind for the exam. The new route asks for \(PlannerInsights.duration((route.neededPerDay ?? 0) * 60)) a day.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button {
                        reroute()
                    } label: {
                        Label("Reroute", systemImage: "arrow.triangle.branch")
                    }
                } footer: {
                    Text("Moves unfinished study tasks from past days to today and plans today's route at the new pace.")
                }
            }
            Section {
                ForEach(route.today, id: \.self) { index in
                    if index < map.stations.count {
                        Button {
                            open(map.stations[index])
                        } label: {
                            HStack {
                                Text(map.stations[index].title).foregroundStyle(Color(uiColor: .label)).lineLimit(2)
                                Spacer()
                                Text("\(minutesLeft(index)) min").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    addRoute()
                } label: {
                    Label("Add Today's Route to the Planner", systemImage: "calendar.badge.plus")
                }
                .disabled(route.today.isEmpty)
            } header: {
                Text("Today's Route")
            } footer: {
                Text("Nothing goes into the Planner until you add it. Each stop becomes a task linked to its note, with spaced reviews when done.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func stationRow(_ label: String, _ station: KnowledgeStation, icon: String, tint: Color) -> some View {
        Button {
            open(station)
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                VStack(alignment: .leading) {
                    Text(trMessage(label)).font(.caption).foregroundStyle(.secondary)
                    Text(tr(station.title)).foregroundStyle(Color(uiColor: .label)).lineLimit(2)
                }
            }
        }
    }

    private func minutesLeft(_ index: Int) -> Int {
        guard index < progress.count else { return map.minutesPerStation }
        let left: Double = (1 - progress[index].value) * Double(map.minutesPerStation)
        return max(Int(left.rounded(.up)), 5)
    }

    private func addRoute() {
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(18 * 3600)
        var added = 0
        for index in route.today where index < map.stations.count {
            let station = map.stations[index]
            let title = studyTitle(station)
            guard !workspace.tasks.contains(where: { $0.title == title && $0.status != .done }) else { continue }
            var task = PlanTask(title: title, dueDate: today)
            task.noteID = station.noteID
            task.chapterTitle = map.bookID == nil ? nil : station.title
            task.estimateMinutes = minutesLeft(index)
            task.schedulesReviews = station.noteID != nil ? true : nil
            task.tags = [map.title.replacingOccurrences(of: "#", with: "")]
            task.notes = "From the Knowledge GPS map “\(map.title)”."
            workspace.save(task)
            added += 1
        }
        let stops = added == 1 ? "stop" : "stops"
        CommandCenter.shared.say(added == 0 ? "Today's route is already in the Planner" : "Added \(added) \(stops) to today")
    }

    private func reroute() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let titles = Set(map.stations.map(studyTitle))
        let marker = "From the Knowledge GPS map “\(map.title)”."
        for task in workspace.tasks where titles.contains(task.title) && task.status != .done && task.notes == marker {
            if let due = task.dueDate, due < startOfToday {
                var moved = task
                moved.dueDate = startOfToday.addingTimeInterval(18 * 3600)
                workspace.save(moved)
            }
        }
        addRoute()
    }
}

// MARK: Station

private struct StationSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let mapID: UUID
    let stationID: UUID
    let evidence: KnowledgeEvidence

    private var map: KnowledgeMap? { workspace.knowledgeMaps.first(where: { $0.id == mapID }) }
    private var station: KnowledgeStation? { map?.stations.first(where: { $0.id == stationID }) }

    /// Worked out from the station as it is now (after a new mark too).
    private var progress: StationProgress {
        guard let map, let station else {
            return StationProgress(reading: nil, memory: nil, focusMinutes: 0, quizzes: nil, mark: .none, value: 0)
        }
        return KnowledgeGPS.progress(of: station, in: map, evidence: evidence)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let station {
                    Section {
                        if station.noteID != nil {
                            Button {
                                dismiss()
                                _ = KnowledgeGPS.go(to: station)
                            } label: {
                                Label(station.firstPage == nil ? "Open" : "Open at This Chapter", systemImage: "book")
                            }
                        }
                        Button {
                            focus(on: station)
                        } label: {
                            Label("Focus on This", systemImage: "play.circle.fill")
                        }
                    }
                    Section("How Far") {
                        ProgressView(value: progress.value) {
                            Text("\(Int(progress.value * 100))% overall")
                        }
                        .tint(.green)
                        if let reading = progress.reading {
                            LabeledContent("Reading", value: "\(Int(reading * 100))%")
                        }
                        if let memory = progress.memory {
                            LabeledContent("Flashcard memory", value: "\(Int(memory * 100))%")
                        }
                        if let quiz = progress.quizzes {
                            LabeledContent("Best quiz", value: "\(Int(quiz * 100))%")
                        }
                        LabeledContent("Focus time", value: "\(progress.focusMinutes) min")
                    }
                    Section {
                        Picker("Mark", selection: Binding(get: { station.mark }, set: { setMark($0) })) {
                            ForEach(KnowledgeStation.Mark.allCases) { Text(tr($0.title)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Your Mark")
                    } footer: {
                        Text("Your own judgement. The map takes whichever is higher: your mark or what InkPad sees.")
                    }
                    Section("Linked") {
                        Picker("Note or Book", selection: Binding(get: { station.noteID }, set: { setNote($0) })) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { note in
                                Text(tr(note.title)).tag(Optional(note.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                        if let first = station.firstPage, let last = station.lastPage {
                            LabeledContent("Pages", value: "\(first + 1)–\(last + 1)")
                        }
                    }
                }
            }
            .navigationTitle(station?.title ?? "Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func update(_ change: (inout KnowledgeStation) -> Void) {
        guard var map, let index = map.stations.firstIndex(where: { $0.id == stationID }) else { return }
        change(&map.stations[index])
        workspace.save(map)
    }

    private func setMark(_ mark: KnowledgeStation.Mark) {
        update { $0.mark = mark }
    }

    private func setNote(_ id: UUID?) {
        update { $0.noteID = id }
    }

    /// A planner task for the station, and Flowmodoro on it.
    private func focus(on station: KnowledgeStation) {
        let title = "Study: \(station.title)"
        let existing: PlanTask? = workspace.tasks.first(where: { $0.title == title && $0.status != .done })
        var task = existing ?? PlanTask(title: title, dueDate: Date())
        if existing == nil {
            task.noteID = station.noteID
            task.chapterTitle = map?.bookID == nil ? nil : station.title
            task.estimateMinutes = map?.minutesPerStation
            workspace.save(task)
        }
        dismiss()
        FocusLauncher.focus(on: task, workspace: workspace)
    }
}

// MARK: Settings

private struct MapSettingsSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let mapID: UUID
    @State private var newStation = ""

    private var map: KnowledgeMap? { workspace.knowledgeMaps.first(where: { $0.id == mapID }) }

    var body: some View {
        NavigationStack {
            Form {
                if let map {
                    Section("Map") {
                        TextField("Name", text: Binding(get: { map.title }, set: { value in change { $0.title = value } }))
                        Toggle("Exam Date", isOn: Binding(get: { map.examDate != nil }, set: { on in
                            change { $0.examDate = on ? Calendar.current.date(byAdding: .day, value: 30, to: Date()) : nil }
                        }))
                        if let exam = map.examDate {
                            DatePicker("Date", selection: Binding(get: { exam }, set: { value in change { $0.examDate = value } }), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        }
                        Stepper("About \(map.minutesPerStation) min per station", value: Binding(get: { map.minutesPerStation }, set: { value in change { $0.minutesPerStation = value } }), in: 10...600, step: 5)
                    }
                    Section {
                        ForEach(map.stations) { station in
                            Text(tr(station.title))
                        }
                        .onDelete { offsets in change { $0.stations.remove(atOffsets: offsets) } }
                        .onMove { from, to in change { $0.stations.move(fromOffsets: from, toOffset: to) } }
                        HStack {
                            TextField("New station", text: $newStation)
                                .onSubmit(addStation)
                            Button("Add", action: addStation)
                                .disabled(newStation.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("Stations")
                    } footer: {
                        Text("Swipe to delete; hold and drag to reorder.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Map Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func change(_ edit: (inout KnowledgeMap) -> Void) {
        guard var map else { return }
        edit(&map)
        workspace.save(map)
    }

    private func addStation() {
        let title = newStation.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        change { $0.stations.append(KnowledgeStation(title: title)) }
        newStation = ""
    }
}

extension KnowledgeGPS {
    /// Opens the station's note or book at its first page. Returns false
    /// when the station has nothing to open (a hand-made stop).
    @MainActor
    static func go(to station: KnowledgeStation) -> Bool {
        guard let noteID = station.noteID else { return false }
        if let page = station.firstPage {
            CommandCenter.shared.openNote(noteID, pdfPage: page)
        } else {
            CommandCenter.shared.openNote(noteID)
        }
        return true
    }
}
