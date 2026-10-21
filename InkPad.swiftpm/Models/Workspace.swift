import Foundation

// MARK: Planner

struct PlanTask: Codable, Identifiable, Equatable {
    enum Status: String, Codable, CaseIterable, Identifiable {
        case todo, inProgress, done
        var id: Self { self }
        var title: String {
            switch self {
            case .todo: "To Do"
            case .inProgress: "In Progress"
            case .done: "Done"
            }
        }
        var systemImage: String {
            switch self {
            case .todo: "circle"
            case .inProgress: "circle.lefthalf.filled"
            case .done: "checkmark.circle.fill"
            }
        }
    }

    enum Priority: String, Codable, CaseIterable, Identifiable {
        case low, medium, high
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    let id: UUID
    var title: String
    var notes: String
    var status: Status
    var priority: Priority
    var dueDate: Date?
    var tags: [String]
    let createdAt: Date

    init(title: String = "", status: Status = .todo, dueDate: Date? = nil) {
        id = UUID()
        self.title = title
        notes = ""
        self.status = status
        priority = .medium
        self.dueDate = dueDate
        tags = []
        createdAt = Date()
    }
}

// MARK: Expenses

struct Expense: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case expense, income
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    enum Category: String, Codable, CaseIterable, Identifiable {
        case food, transport, shopping, bills, health, education, entertainment, salary, other
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .food: "fork.knife"
            case .transport: "car"
            case .shopping: "bag"
            case .bills: "doc.text"
            case .health: "cross.case"
            case .education: "book"
            case .entertainment: "gamecontroller"
            case .salary: "banknote"
            case .other: "ellipsis.circle"
            }
        }
    }

    let id: UUID
    var title: String
    var amount: Decimal
    var kind: Kind
    var category: Category
    var date: Date
    var note: String

    init(kind: Kind = .expense) {
        id = UUID()
        title = ""
        amount = 0
        self.kind = kind
        category = kind == .income ? .salary : .food
        date = Date()
        note = ""
    }
}

/// The persisted planner and expenses (`workspace.json`).
struct WorkspaceFile: Codable {
    static let currentVersion = 1

    var version: Int
    var tasks: [PlanTask]
    var expenses: [Expense]
    /// Monthly spending budget; `nil` means none.
    var monthlyBudget: Decimal?
    /// ISO 4217 code, e.g. "USD".
    var currencyCode: String?
}
