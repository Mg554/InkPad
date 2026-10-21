import Foundation

/// Owns the planner tasks and expenses (`Documents/InkPad/workspace.json`).
/// Like the note library, it opens read-only rather than overwrite a file
/// it cannot read.
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var tasks: [PlanTask] = []
    @Published private(set) var expenses: [Expense] = []
    @Published private(set) var monthlyBudget: Decimal?
    @Published private(set) var currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    @Published var errorMessage: String?
    @Published private(set) var isReadOnly = false

    private let fileURL: URL

    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InkPad", isDirectory: true)
        fileURL = root.appendingPathComponent("workspace.json")
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

    func setCurrency(_ code: String) {
        guard canWrite() else { return }
        currencyCode = code
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
            currencyCode: currencyCode
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
