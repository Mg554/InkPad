import Foundation

/// Owns the planner tasks, expenses, mind maps and slide decks
/// (`Documents/InkPad/workspace.json`, with slide pictures in
/// `Documents/InkPad/decks/<id>/`). Like the note library, it opens
/// read-only rather than overwrite a file it cannot read.
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var tasks: [PlanTask] = []
    @Published private(set) var expenses: [Expense] = []
    @Published private(set) var monthlyBudget: Decimal?
    @Published private(set) var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    @Published private(set) var showsCents = false
    @Published private(set) var mindMaps: [MindMap] = []
    @Published private(set) var decks: [SlideDeck] = []
    @Published private(set) var flashcardDecks: [FlashcardDeck] = []
    @Published private(set) var quizzes: [Quiz] = []
    @Published private(set) var studyChats: [StudyChat] = []
    @Published private(set) var flowTasks: [FlowTask] = []
    @Published private(set) var flowSessions: [FlowSession] = []
    @Published private(set) var flowTimer: FlowTimer?
    /// Break length in percent of the work time.
    @Published private(set) var flowBreakShare = Flowmodoro.defaultBreakShare
    @Published private(set) var distractions: [Distraction] = []
    @Published private(set) var knowledgeMaps: [KnowledgeMap] = []
    @Published var errorMessage: String?
    @Published private(set) var isReadOnly = false

    private let fileURL: URL
    private let decksURL: URL

    init(rootURL: URL? = nil) {
        let root = rootURL ?? LibraryStore.defaultRootURL
        fileURL = root.appendingPathComponent("workspace.json")
        decksURL = root.appendingPathComponent("decks", isDirectory: true)
        load()
    }

    // MARK: Tasks

    func save(_ task: PlanTask) {
        guard canWrite() else { return }
        var saved = task
        var finished = false
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            if tasks[index].status != task.status {
                saved.completedAt = task.status == .done ? Date() : nil
                finished = task.status == .done
            }
            tasks[index] = saved
        } else {
            if task.status == .done { saved.completedAt = Date() }
            tasks.append(saved)
        }
        if finished { scheduleReview(after: saved) }
        persist()
    }

    func setStatus(_ status: PlanTask.Status, for id: UUID) {
        guard canWrite(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        // Only a real change moves the completion date (drags may repeat it).
        guard tasks[index].status != status else { return }
        tasks[index].status = status
        tasks[index].completedAt = status == .done ? Date() : nil
        if status == .done { scheduleReview(after: tasks[index]) }
        persist()
    }

    /// Study-linked tasks: the next spaced review becomes a task of its own.
    private func scheduleReview(after task: PlanTask) {
        guard let days = task.nextReviewDays else { return }
        let step = (task.reviewStep ?? 0) + 1
        // Only once per step, even if the task is reopened and finished again.
        let exists = tasks.contains { $0.reviewStep == step && $0.noteID == task.noteID && $0.chapterTitle == task.chapterTitle && $0.title == Self.reviewTitle(task) }
        guard !exists else { return }
        let due = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))
        var review = PlanTask(title: Self.reviewTitle(task), dueDate: due)
        review.notes = "Review \(step) of 3 (spaced repetition)."
        review.tags = task.tags
        review.priority = task.priority
        review.noteID = task.noteID
        review.chapterTitle = task.chapterTitle
        review.schedulesReviews = true
        review.reviewStep = step
        review.estimateMinutes = 15
        tasks.append(review)
    }

    private static func reviewTitle(_ task: PlanTask) -> String {
        let base = task.title.hasPrefix("Review: ") ? String(task.title.dropFirst(8)) : task.title
        return "Review: \(base)"
    }

    func deleteTask(_ id: UUID) {
        guard canWrite() else { return }
        tasks.removeAll { $0.id == id }
        // A Focus on This session on it stops.
        if flowTimer?.planTaskID == id, flowTimer?.phase == .working { flowTimer = nil }
        persist()
    }

    // MARK: Expenses

    func save(_ expense: Expense) {
        guard canWrite() else { return }
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
        } else {
            expenses.append(expense)
        }
        persist()
    }

    func deleteExpense(_ id: UUID) {
        guard canWrite() else { return }
        expenses.removeAll { $0.id == id }
        persist()
    }

    func setMonthlyBudget(_ budget: Decimal?) {
        guard canWrite() else { return }
        monthlyBudget = budget.flatMap { $0 > 0 ? $0 : nil }
        persist()
    }

    var money: MoneyFormatter {
        MoneyFormatter(currencyCode: currencyCode, showsCents: showsCents)
    }

    func setShowsCents(_ shows: Bool) {
        guard canWrite() else { return }
        showsCents = shows
        persist()
    }

    func setCurrency(_ code: String) {
        guard canWrite() else { return }
        currencyCode = code
        persist()
    }

    // MARK: Mind maps

    func save(_ map: MindMap) {
        guard canWrite() else { return }
        var map = map
        map.modifiedAt = Date()
        if let index = mindMaps.firstIndex(where: { $0.id == map.id }) {
            mindMaps[index] = map
        } else {
            mindMaps.append(map)
        }
        persist()
    }

    func deleteMindMap(_ id: UUID) {
        guard canWrite() else { return }
        mindMaps.removeAll { $0.id == id }
        persist()
    }

    // MARK: Slide decks

    func save(_ deck: SlideDeck) {
        guard canWrite() else { return }
        var deck = deck
        deck.modifiedAt = Date()
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index] = deck
        } else {
            decks.append(deck)
        }
        persist()
    }

    func deleteDeck(_ id: UUID) {
        guard canWrite() else { return }
        decks.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: deckDirectory(id))
        persist()
    }

    /// Where a deck's pictures are stored.
    func deckDirectory(_ id: UUID) -> URL {
        decksURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Stores a picture for a deck's slide. Returns its file name.
    func addDeckImage(_ jpeg: Data, to deckID: UUID) -> String? {
        guard canWrite() else { return nil }
        let directory = deckDirectory(deckID)
        let file = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: directory.appendingPathComponent(file), options: .atomic)
            return file
        } catch {
            errorMessage = "Could not save a slide picture: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Study

    func save(_ deck: FlashcardDeck) {
        guard canWrite() else { return }
        var deck = deck
        deck.modifiedAt = Date()
        if let index = flashcardDecks.firstIndex(where: { $0.id == deck.id }) {
            flashcardDecks[index] = deck
        } else {
            flashcardDecks.append(deck)
        }
        persist()
    }

    func deleteFlashcardDeck(_ id: UUID) {
        guard canWrite() else { return }
        flashcardDecks.removeAll { $0.id == id }
        persist()
    }

    /// Records a review of one card.
    func review(card cardID: UUID, in deckID: UUID, rating: Flashcard.Rating) {
        guard canWrite(),
              let deckIndex = flashcardDecks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = flashcardDecks[deckIndex].cards.firstIndex(where: { $0.id == cardID })
        else { return }
        flashcardDecks[deckIndex].cards[cardIndex].review(rating)
        persist()
    }

    var dueCardCount: Int {
        flashcardDecks.reduce(0) { $0 + $1.dueCount }
    }

    func save(_ quiz: Quiz) {
        guard canWrite() else { return }
        if let index = quizzes.firstIndex(where: { $0.id == quiz.id }) {
            quizzes[index] = quiz
        } else {
            quizzes.append(quiz)
        }
        persist()
    }

    func save(_ chat: StudyChat) {
        guard canWrite() else { return }
        if let index = studyChats.firstIndex(where: { $0.id == chat.id }) {
            studyChats[index] = chat
        } else {
            studyChats.append(chat)
        }
        persist()
    }

    func deleteStudyChat(_ id: UUID) {
        guard canWrite() else { return }
        studyChats.removeAll { $0.id == id }
        persist()
    }

    /// Chats about exactly these notes (none: all notes), newest first.
    func chats(about ids: [UUID]) -> [StudyChat] {
        studyChats.filter { $0.isAbout(ids) }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func deleteQuiz(_ id: UUID) {
        guard canWrite() else { return }
        quizzes.removeAll { $0.id == id }
        persist()
    }

    // MARK: Flowmodoro

    func addFlowTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canWrite(), !trimmed.isEmpty else { return }
        flowTasks.append(FlowTask(title: trimmed))
        persist()
    }

    func renameFlowTask(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canWrite(), !trimmed.isEmpty, let index = flowTasks.firstIndex(where: { $0.id == id }) else { return }
        flowTasks[index].title = trimmed
        if flowTimer?.taskID == id { flowTimer?.taskTitle = trimmed }
        persist()
    }

    func toggleFlowTask(_ id: UUID) {
        guard canWrite(), let index = flowTasks.firstIndex(where: { $0.id == id }) else { return }
        flowTasks[index].isDone.toggle()
        persist()
    }

    func deleteFlowTask(_ id: UUID) {
        guard canWrite() else { return }
        flowTasks.removeAll { $0.id == id }
        // The history keeps the sessions; it stores the task's title.
        if flowTimer?.taskID == id, flowTimer?.phase == .working { flowTimer = nil }
        persist()
    }

    func moveFlowTasks(from source: IndexSet, to destination: Int) {
        guard canWrite() else { return }
        flowTasks.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func setFlowBreakShare(_ share: Int) {
        guard canWrite() else { return }
        flowBreakShare = share
        persist()
    }

    /// Starts the work stopwatch for a task. Not while work is already running.
    func startFlowWork(on id: UUID) {
        guard canWrite(), flowTimer?.phase != .working,
              let task = flowTasks.first(where: { $0.id == id }), !task.isDone
        else { return }
        flowTimer = FlowTimer(
            taskID: id,
            taskTitle: task.title,
            phase: .working,
            workStartedAt: Date(),
            workSeconds: 0,
            breakSeconds: 0,
            breakStartedAt: nil
        )
        persist()
    }

    /// Stops work: the session goes into the history and the break is earned.
    func stopFlowWork() {
        guard canWrite(), var timer = flowTimer, timer.phase == .working else { return }
        let worked = timer.workElapsed(at: Date())
        timer.workSeconds = worked
        timer.breakSeconds = Flowmodoro.breakSeconds(forWork: worked, share: flowBreakShare)
        timer.phase = .breakReady
        flowTimer = timer
        flowSessions.append(FlowSession(
            id: UUID(),
            taskTitle: timer.taskTitle,
            workSeconds: worked,
            breakSeconds: timer.breakSeconds,
            endedAt: Date(),
            planTaskID: timer.planTaskID
        ))
        // "Focus on This": the time is logged on the planner task.
        if let planID = timer.planTaskID, let index = tasks.firstIndex(where: { $0.id == planID }) {
            tasks[index].focusSeconds = (tasks[index].focusSeconds ?? 0) + worked
        }
        persist()
    }

    /// "Focus on This": starts the work stopwatch for a planner task.
    func startFocus(onPlanTask id: UUID) {
        // Not over running work or an earned break that hasn't been taken.
        guard canWrite(), flowTimer == nil,
              let index = tasks.firstIndex(where: { $0.id == id })
        else { return }
        if tasks[index].status == .todo { tasks[index].status = .inProgress }
        let title = tasks[index].title.isEmpty ? "Untitled" : tasks[index].title
        flowTimer = FlowTimer(
            taskID: id,
            taskTitle: title,
            phase: .working,
            workStartedAt: Date(),
            workSeconds: 0,
            breakSeconds: 0,
            breakStartedAt: nil,
            planTaskID: id
        )
        persist()
    }

    /// Focus Mode: starts the stopwatch on a Flowmodoro task with this
    /// title, making the task if needed. Returns whether work is running.
    @discardableResult
    func startFocusSession(title: String) -> Bool {
        guard canWrite() else { return false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Focus" : title
        // Already focusing on this: keep going. Other work is logged and stopped.
        if flowTimer?.phase == .working, flowTimer?.taskTitle == name { return true }
        if flowTimer?.phase == .working { stopFlowWork() }
        // An earned break is skipped when a new focus session starts.
        if flowTimer != nil { flowTimer = nil }
        if !flowTasks.contains(where: { $0.title == name && !$0.isDone }) {
            flowTasks.append(FlowTask(title: name))
        }
        guard let task = flowTasks.first(where: { $0.title == name && !$0.isDone }) else { return false }
        startFlowWork(on: task.id)
        return flowTimer?.phase == .working
    }

    /// Time blocks for today (Plan My Day).
    func schedule(_ plan: [UUID: Date], replacing candidates: Set<UUID> = []) {
        guard canWrite() else { return }
        for index in tasks.indices {
            if let start = plan[tasks[index].id] {
                tasks[index].scheduledAt = start
            } else if candidates.contains(tasks[index].id) {
                // Didn't fit this time: no old block left on the timeline.
                tasks[index].scheduledAt = nil
            }
        }
        persist()
    }

    func setMatrix(important: Bool, urgent: Bool, for id: UUID) {
        guard canWrite(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isImportant = important
        tasks[index].isUrgent = urgent
        persist()
    }

    // MARK: Knowledge GPS

    func save(_ map: KnowledgeMap) {
        guard canWrite() else { return }
        if let index = knowledgeMaps.firstIndex(where: { $0.id == map.id }) {
            knowledgeMaps[index] = map
        } else {
            knowledgeMaps.append(map)
        }
        persist()
    }

    func deleteKnowledgeMap(_ id: UUID) {
        guard canWrite() else { return }
        knowledgeMaps.removeAll { $0.id == id }
        persist()
    }

    // MARK: Distraction Box

    func addDistraction(_ distraction: Distraction) {
        guard canWrite() else { return }
        distractions.insert(distraction, at: 0)
        persist()
    }

    func updateDistraction(_ distraction: Distraction) {
        guard canWrite(), let index = distractions.firstIndex(where: { $0.id == distraction.id }) else { return }
        distractions[index] = distraction
        persist()
    }

    /// Only the text (handwriting read later), keeping what changed meanwhile.
    func setDistractionText(_ text: String, for id: UUID) {
        guard canWrite(), let index = distractions.firstIndex(where: { $0.id == id }) else { return }
        distractions[index].text = text
        persist()
    }

    func deleteDistraction(_ id: UUID) {
        guard canWrite() else { return }
        distractions.removeAll { $0.id == id }
        persist()
    }

    func startFlowBreak() {
        guard canWrite(), var timer = flowTimer, timer.phase == .breakReady else { return }
        timer.phase = .onBreak
        timer.breakStartedAt = Date()
        flowTimer = timer
        persist()
    }

    /// Ends the break (when it runs out, or skipped) and clears the timer.
    func endFlowBreak() {
        guard canWrite(), flowTimer != nil, flowTimer?.phase != .working else { return }
        flowTimer = nil
        persist()
    }

    /// Throws away the work in progress without recording it.
    func discardFlowWork() {
        guard canWrite(), flowTimer?.phase == .working else { return }
        flowTimer = nil
        persist()
    }

    func clearFlowHistory() {
        guard canWrite() else { return }
        flowSessions = []
        persist()
    }

    // MARK: Persistence

    /// Reads everything again from disk, after a backup was restored.
    func reload() {
        tasks = []
        expenses = []
        monthlyBudget = nil
        currencyCode = Locale.current.currency?.identifier ?? "USD"
        showsCents = false
        mindMaps = []
        decks = []
        flashcardDecks = []
        quizzes = []
        studyChats = []
        flowTasks = []
        flowSessions = []
        flowTimer = nil
        flowBreakShare = Flowmodoro.defaultBreakShare
        distractions = []
        knowledgeMaps = []
        isReadOnly = false
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let file = try JSONDecoder.inkpad.decode(WorkspaceFile.self, from: Data(contentsOf: fileURL))
            guard file.version <= WorkspaceFile.currentVersion else {
                throw StoreError.newerFormat(file: "workspace.json", version: file.version)
            }
            tasks = file.tasks
            expenses = file.expenses
            monthlyBudget = file.monthlyBudget
            if let code = file.currencyCode { currencyCode = code }
            showsCents = file.showsCents ?? false
            mindMaps = file.mindMaps ?? []
            decks = file.slideDecks ?? []
            flashcardDecks = file.flashcardDecks ?? []
            quizzes = file.quizzes ?? []
            studyChats = file.studyChats ?? []
            flowTasks = file.flowTasks ?? []
            flowSessions = file.flowSessions ?? []
            flowTimer = file.flowTimer
            flowBreakShare = file.flowBreakShare ?? Flowmodoro.defaultBreakShare
            distractions = file.distractions ?? []
            knowledgeMaps = file.knowledgeMaps ?? []
        } catch {
            isReadOnly = true
            errorMessage = "Your planner and expenses could not be read (\(error.localizedDescription)). "
                + "They opened read-only so nothing is overwritten."
        }
    }

    private func persist() {
        let file = WorkspaceFile(
            version: WorkspaceFile.currentVersion,
            tasks: tasks,
            expenses: expenses,
            monthlyBudget: monthlyBudget,
            currencyCode: currencyCode,
            showsCents: showsCents,
            mindMaps: mindMaps,
            slideDecks: decks,
            flashcardDecks: flashcardDecks,
            quizzes: quizzes,
            studyChats: studyChats,
            flowTasks: flowTasks,
            flowSessions: flowSessions,
            flowTimer: flowTimer,
            flowBreakShare: flowBreakShare,
            distractions: distractions,
            knowledgeMaps: knowledgeMaps
        )
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.inkpad.encode(file).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func canWrite() -> Bool {
        if isReadOnly {
            errorMessage = "The planner is read-only because its file could not be read safely."
        }
        return !isReadOnly
    }
}
