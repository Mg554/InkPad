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

/// The persisted planner, expenses, mind maps and slide decks (`workspace.json`).
struct WorkspaceFile: Codable {
    static let currentVersion = 1

    var version: Int
    var tasks: [PlanTask]
    var expenses: [Expense]
    /// Monthly spending budget; `nil` means none.
    var monthlyBudget: Decimal?
    /// ISO 4217 code, e.g. "USD".
    var currencyCode: String?
    /// `false` (default) shows whole amounts without decimals.
    var showsCents: Bool?
    var mindMaps: [MindMap]?
    var slideDecks: [SlideDeck]?
    var flashcardDecks: [FlashcardDeck]?
    var quizzes: [Quiz]?
    var flowTasks: [FlowTask]?
    var flowSessions: [FlowSession]?
    var flowTimer: FlowTimer?
    var flowBreakShare: Int?
}

// MARK: Mind maps

struct MindNode: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    /// `nil` for the central topic.
    var parentID: UUID?
    /// Position in map coordinates; the central topic starts at (0, 0).
    var x: Double
    var y: Double
    /// `nil` uses the branch's default color.
    var color: FolderColor?

    init(text: String, parentID: UUID?, x: Double, y: Double, color: FolderColor? = nil) {
        id = UUID()
        self.text = text
        self.parentID = parentID
        self.x = x
        self.y = y
        self.color = color
    }
}

struct MindMap: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var nodes: [MindNode]
    let createdAt: Date
    var modifiedAt: Date

    init(title: String) {
        id = UUID()
        self.title = title
        nodes = [MindNode(text: title, parentID: nil, x: 0, y: 0, color: .purple)]
        createdAt = Date()
        modifiedAt = Date()
    }

    var root: MindNode? { nodes.first { $0.parentID == nil } }

    func children(of id: UUID) -> [MindNode] {
        nodes.filter { $0.parentID == id }
    }

    /// The node and everything below it.
    func subtree(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var queue = [id]
        while let next = queue.popLast() {
            for child in children(of: next) where result.insert(child.id).inserted {
                queue.append(child.id)
            }
        }
        return result
    }

    /// Lays the map out as a tree growing right from the central topic,
    /// each branch getting vertical room for its leaves.
    mutating func autoLayout(horizontalSpacing: Double = 230, verticalSpacing: Double = 64) {
        guard let root else { return }
        var leafCounts: [UUID: Int] = [:]
        func leaves(_ id: UUID, visited: inout Set<UUID>) -> Int {
            guard visited.insert(id).inserted else { return 0 }
            let kids = children(of: id)
            let count = kids.isEmpty ? 1 : kids.reduce(0) { $0 + leaves($1.id, visited: &visited) }
            leafCounts[id] = count
            return count
        }
        var visited: Set<UUID> = []
        _ = leaves(root.id, visited: &visited)

        var positions: [UUID: (Double, Double)] = [:]
        func place(_ id: UUID, depth: Int, top: Double) {
            let span = Double(leafCounts[id] ?? 1) * verticalSpacing
            positions[id] = (Double(depth) * horizontalSpacing, top + span / 2)
            var childTop = top
            for child in children(of: id) where leafCounts[child.id] != nil && positions[child.id] == nil {
                place(child.id, depth: depth + 1, top: childTop)
                childTop += Double(leafCounts[child.id] ?? 1) * verticalSpacing
            }
        }
        let total = Double(leafCounts[root.id] ?? 1) * verticalSpacing
        place(root.id, depth: 0, top: -total / 2)
        for index in nodes.indices {
            if let position = positions[nodes[index].id] {
                nodes[index].x = position.0
                nodes[index].y = position.1
            }
        }
    }
}
