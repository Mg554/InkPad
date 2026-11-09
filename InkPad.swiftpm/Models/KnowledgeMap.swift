import Foundation

/// Knowledge GPS: a map of what to learn (a book's chapters, a subject's
/// notes, or stations made by hand), with progress, the next stop, the
/// time left to an exam and a daily route.
struct KnowledgeMap: Codable, Identifiable, Equatable {
    enum Source: Codable, Equatable {
        /// A PDF book note: a station per chapter.
        case book(UUID)
        /// Notes with this tag (without #): a station per note.
        case tag(String)
        /// Stations made by hand (an exam syllabus...).
        case manual
    }

    enum Style: String, Codable, CaseIterable, Identifiable {
        case islands, metro, tree
        var id: Self { self }
        var title: String {
            switch self {
            case .islands: "Islands"
            case .metro: "Metro"
            case .tree: "Skill Tree"
            }
        }
        var systemImage: String {
            switch self {
            case .islands: "map"
            case .metro: "tram"
            case .tree: "tree"
            }
        }
    }

    let id: UUID
    var title: String
    var source: Source
    var style: Style
    var stations: [KnowledgeStation]
    var examDate: Date?
    /// Minutes one station takes, to work out the time left.
    var minutesPerStation: Int
    let createdAt: Date

    init(title: String, source: Source, stations: [KnowledgeStation]) {
        id = UUID()
        self.title = title
        self.source = source
        style = .islands
        self.stations = stations
        examDate = nil
        minutesPerStation = 45
        createdAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = container.value(.title, or: "Map")
        source = container.value(.source, or: Source.manual)
        style = container.value(.style, or: Style.islands)
        stations = container.value(.stations, or: [])
        examDate = container.value(.examDate, or: nil)
        minutesPerStation = container.value(.minutesPerStation, or: 45)
        createdAt = container.value(.createdAt, or: Date())
    }

    var bookID: UUID? {
        if case let .book(id) = source { return id }
        return nil
    }
}

/// One stop on the map.
struct KnowledgeStation: Codable, Identifiable, Equatable {
    /// Marked by hand, like the owner asked: started, understood, mastered.
    enum Mark: String, Codable, CaseIterable, Identifiable {
        case none, started, understood, mastered
        var id: Self { self }
        var title: String {
            switch self {
            case .none: "Not Started"
            case .started: "Started"
            case .understood: "Understood"
            case .mastered: "Mastered"
            }
        }
        var value: Double {
            switch self {
            case .none: 0
            case .started: 0.25
            case .understood: 0.7
            case .mastered: 1
            }
        }
    }

    let id: UUID
    var title: String
    /// The note (or book) it is about.
    var noteID: UUID?
    /// For a book chapter: its PDF pages (zero-based).
    var firstPage: Int?
    var lastPage: Int?
    var mark: Mark

    init(title: String, noteID: UUID? = nil, firstPage: Int? = nil, lastPage: Int? = nil) {
        id = UUID()
        self.title = title
        self.noteID = noteID
        self.firstPage = firstPage
        self.lastPage = lastPage
        mark = .none
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = container.value(.title, or: "Station")
        noteID = container.value(.noteID, or: nil)
        firstPage = container.value(.firstPage, or: nil)
        lastPage = container.value(.lastPage, or: nil)
        mark = container.value(.mark, or: Mark.none)
    }
}

/// How far along one station is, and why.
struct StationProgress {
    var reading: Double?
    var memory: Double?
    var focusMinutes: Int
    var quizzes: Double?
    var mark: KnowledgeStation.Mark
    /// 0...1 overall.
    var value: Double

    enum Level { case fog, started, understood, mastered }

    var level: Level {
        if value >= 0.85 { return .mastered }
        if value >= 0.5 { return .understood }
        if value >= 0.05 { return .started }
        return .fog
    }
}

/// What is known about the learner, gathered once for a map.
struct KnowledgeEvidence {
    /// For each book: the furthest PDF page read.
    var furthestPDFPage: [UUID: Int] = [:]
    var decks: [FlashcardDeck] = []
    var quizzes: [Quiz] = []
    var sessions: [FlowSession] = []
    var tasks: [PlanTask] = []
    /// Notes opened or edited (for subject maps).
    var touchedNotes: Set<UUID> = []
}

enum KnowledgeGPS {
    // MARK: Progress

    static func progress(of station: KnowledgeStation, in map: KnowledgeMap, evidence: KnowledgeEvidence) -> StationProgress {
        var reading: Double?
        if let book = map.bookID, let first = station.firstPage, let last = station.lastPage, let furthest = evidence.furthestPDFPage[book] {
            let pages = Double(max(last - first + 1, 1))
            let read = Double(min(max(furthest - first + 1, 0), last - first + 1))
            reading = read / pages
        } else if let noteID = station.noteID, map.bookID == nil {
            reading = evidence.touchedNotes.contains(noteID) ? 0.6 : nil
        }
        var memory: Double?
        var quiz: Double?
        // In a book map every chapter shares the book: cards and quizzes
        // can't be told apart by chapter, so they count for notes only.
        if let noteID = station.noteID, map.bookID == nil {
            let decks = evidence.decks.filter { $0.sourceNoteIDs.contains(noteID) }
            let strengths = decks.compactMap { $0.memoryStrength() }
            if !strengths.isEmpty { memory = strengths.reduce(0, +) / Double(strengths.count) }
            let scores: [Double] = evidence.quizzes.filter { $0.sourceNoteIDs.contains(noteID) }.compactMap { item in
                guard let best = item.bestScore, !item.questions.isEmpty else { return nil }
                return Double(best) / Double(item.questions.count)
            }
            if !scores.isEmpty { quiz = scores.max() }
        }
        let minutes = focusMinutes(on: station, isBook: map.bookID != nil, evidence: evidence)
        let focus: Double = min(Double(minutes) / Double(max(map.minutesPerStation, 1)), 1)
        // Evidence weighs in by what is known; a hand mark can only raise it.
        var parts: [(Double, Double)] = [(focus, 0.25)]
        if let reading { parts.append((reading, 0.35)) }
        if let memory { parts.append((memory, 0.25)) }
        if let quiz { parts.append((quiz, 0.15)) }
        let weight: Double = parts.reduce(0) { $0 + $1.1 }
        let auto: Double = parts.reduce(0) { $0 + $1.0 * $1.1 } / max(weight, 0.01)
        let value = max(auto, station.mark.value)
        return StationProgress(reading: reading, memory: memory, focusMinutes: minutes, quizzes: quiz, mark: station.mark, value: min(value, 1))
    }

    /// Focus logged on planner tasks about this station, or sessions named after it.
    static func focusMinutes(on station: KnowledgeStation, isBook: Bool, evidence: KnowledgeEvidence) -> Int {
        let studyTitle = "Study: \(station.title)"
        var taskIDs: Set<UUID> = []
        for task in evidence.tasks {
            let sameNote: Bool = station.noteID != nil && task.noteID == station.noteID
            // Book chapters need the chapter named; a note's tasks all count.
            let sameChapter: Bool = isBook ? task.chapterTitle == station.title : (task.chapterTitle == nil || task.chapterTitle == station.title)
            if (sameNote && sameChapter) || task.title == studyTitle {
                taskIDs.insert(task.id)
            }
        }
        var seconds = 0
        for session in evidence.sessions {
            var linked = false
            if let planID = session.planTaskID { linked = taskIDs.contains(planID) }
            if linked || session.taskTitle == studyTitle || session.taskTitle == station.title {
                seconds += session.workSeconds
            }
        }
        return seconds / 60
    }

    // MARK: Navigation

    struct Route {
        /// The station being studied now ("you are here").
        var here: Int?
        var next: Int?
        /// Minutes of study left, all stations.
        var minutesLeft: Int
        /// The learner's daily focus, in minutes (last 7 days, or 60).
        var dailyMinutes: Int
        var daysToFinish: Int
        var daysToExam: Int?
        /// Minutes a day needed to finish by the exam.
        var neededPerDay: Int?
        var isBehind: Bool
        var examPassed: Bool
        /// Today's stops.
        var today: [Int]
    }

    static func route(for map: KnowledgeMap, progress: [StationProgress], sessions: [FlowSession], now: Date = Date()) -> Route {
        let calendar = Calendar.current
        let unfinished = progress.indices.filter { progress[$0].level != .mastered }
        let started: Int? = unfinished.first(where: { progress[$0].level != .fog })
        let here: Int? = started ?? unfinished.first
        // The next stop comes after where you are.
        let after: Int? = unfinished.first(where: { $0 > (here ?? -1) })
        let next: Int? = after ?? unfinished.first(where: { $0 != here })
        var minutesLeft = 0
        for index in unfinished {
            let left: Double = (1 - progress[index].value) * Double(map.minutesPerStation)
            minutesLeft += Int(left.rounded(.up))
        }
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let recent = sessions.filter { $0.endedAt >= weekAgo }.reduce(0) { $0 + $1.workSeconds }
        let daily = recent > 0 ? max(recent / 60 / 7, 15) : 60
        let daysToFinish = Int((Double(minutesLeft) / Double(daily)).rounded(.up))
        var daysToExam: Int?
        var needed: Int?
        var passed = false
        if let exam = map.examDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: exam)).day ?? 0
            if days < 0 {
                passed = true
            } else {
                daysToExam = days
                // The exam day itself still counts as a study day.
                needed = Int((Double(minutesLeft) / Double(days + 1)).rounded(.up))
            }
        }
        var behind = false
        if let daysToExam { behind = minutesLeft > 0 && daysToFinish > daysToExam + 1 }
        // Today's stops: enough minutes for the needed pace (or the usual day).
        let budget = max(needed ?? daily, 20)
        var today: [Int] = []
        var used = 0
        for index in unfinished {
            let left: Double = (1 - progress[index].value) * Double(map.minutesPerStation)
            today.append(index)
            used += Int(left.rounded(.up))
            if used >= budget || today.count >= 6 { break }
        }
        return Route(here: here, next: next, minutesLeft: minutesLeft, dailyMinutes: daily, daysToFinish: daysToFinish,
                     daysToExam: daysToExam, neededPerDay: needed, isBehind: behind, examPassed: passed, today: today)
    }

    // MARK: Making maps

    static func stations(forBook noteID: UUID, chapters: [BookChapter]) -> [KnowledgeStation] {
        chapters.filter { $0.depth == 0 }.map { chapter in
            KnowledgeStation(title: chapter.title, noteID: noteID, firstPage: chapter.firstPage, lastPage: chapter.lastPage)
        }
    }

    static func stations(forTag tag: String, notes: [NoteSummary]) -> [KnowledgeStation] {
        notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { note in
            KnowledgeStation(title: note.title, noteID: note.id)
        }
    }

    /// One station per non-empty line.
    static func stations(fromLines text: String) -> [KnowledgeStation] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { KnowledgeStation(title: $0) }
    }
}
