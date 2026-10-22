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
    @Published var errorMessage: String?
    @Published private(set) var isReadOnly = false

    private let fileURL: URL
    private let decksURL: URL

    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InkPad", isDirectory: true)
        fileURL = root.appendingPathComponent("workspace.json")
        decksURL = root.appendingPathComponent("decks", isDirectory: true)
        load()
    }

    // MARK: Tasks

    func save(_ task: PlanTask) {
        guard canWrite() else { return }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        persist()
    }

    func setStatus(_ status: PlanTask.Status, for id: UUID) {
        guard canWrite(), let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
        persist()
    }

    func deleteTask(_ id: UUID) {
        guard canWrite() else { return }
        tasks.removeAll { $0.id == id }
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

    func deleteQuiz(_ id: UUID) {
        guard canWrite() else { return }
        quizzes.removeAll { $0.id == id }
        persist()
    }

    // MARK: Persistence

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
            quizzes: quizzes
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
