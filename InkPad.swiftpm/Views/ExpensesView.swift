import Charts
import SwiftUI

/// Notion-style budget tracker: monthly totals, a budget, spending by
/// category, and the month's transactions.
struct ExpensesView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var editing: Expense?
    @State private var isEditingSettings = false

    private var currency: String { workspace.currencyCode }

    private var monthItems: [Expense] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return workspace.expenses
            .filter { interval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var spent: Decimal { total(monthItems.filter { $0.kind == .expense }) }
    private var earned: Decimal { total(monthItems.filter { $0.kind == .income }) }

    var body: some View {
        List {
            Section {
                monthPicker
                summary
                if let budget = workspace.monthlyBudget {
                    budgetBar(budget)
                }
            }

            if !monthItems.filter({ $0.kind == .expense }).isEmpty {
                Section("Spending by Category") {
                    categoryChart
                }
            }

            ForEach(days, id: \.self) { day in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(monthItems.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { item in
                        row(item)
                    }
                }
            }
        }
        .overlay {
            if monthItems.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "creditcard",
                    description: Text("Tap + to add an expense or income for this month.")
                )
                .padding(.top, 200)
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isEditingSettings = true
                } label: {
                    Label("Budget & Currency", systemImage: "slider.horizontal.3")
                }
                Menu {
                    Button {
                        editing = newItem(.expense)
                    } label: {
                        Label("Expense", systemImage: "minus.circle")
                    }
                    Button {
                        editing = newItem(.income)
                    } label: {
                        Label("Income", systemImage: "plus.circle")
                    }
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $editing) { item in
            ExpenseEditor(expense: item, currency: currency)
        }
        .sheet(isPresented: $isEditingSettings) {
            BudgetSettings()
        }
    }

    // MARK: Sections

    private var monthPicker: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.bold())
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.borderless)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            summaryCard("Income", earned, color: .green)
            summaryCard("Spent", spent, color: .red)
            summaryCard("Balance", earned - spent, color: earned >= spent ? .blue : .orange)
        }
    }

    private func summaryCard(_ title: String, _ value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currency))
                .font(.title3.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func budgetBar(_ budget: Decimal) -> some View {
        let used = budget > 0 ? min(NSDecimalNumber(decimal: spent / budget).doubleValue, 1.5) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Budget")
                Spacer()
                Text("\(spent.formatted(.currency(code: currency))) of \(budget.formatted(.currency(code: currency)))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: min(used, 1))
                .tint(used < 0.8 ? .green : used < 1 ? .orange : .red)
            if used >= 1 {
                Text("Over budget by \((spent - budget).formatted(.currency(code: currency)))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var categoryChart: some View {
        let totals = Expense.Category.allCases.compactMap { category -> (Expense.Category, Double)? in
            let sum = total(monthItems.filter { $0.kind == .expense && $0.category == category })
            return sum > 0 ? (category, NSDecimalNumber(decimal: sum).doubleValue) : nil
        }
        return HStack(spacing: 24) {
            Chart(totals, id: \.0) { item in
                SectorMark(angle: .value("Amount", item.1), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(by: .value("Category", item.0.title))
            }
            .chartLegend(.hidden)
            .frame(width: 180, height: 180)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(totals, id: \.0) { item in
                    HStack {
                        Label(item.0.title, systemImage: item.0.systemImage)
                        Spacer()
                        Text(item.1, format: .currency(code: currency))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func row(_ item: Expense) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.systemImage)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? item.category.title : item.title)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text((item.kind == .income ? item.amount : -item.amount), format: .currency(code: currency))
                .foregroundStyle(item.kind == .income ? Color.green : Color.primary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = item }
        .swipeActions {
            Button(role: .destructive) {
                workspace.deleteExpense(item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Helpers

    private var days: [Date] {
        let starts = monthItems.map { Calendar.current.startOfDay(for: $0.date) }
        return Array(Set(starts)).sorted(by: >)
    }

    private func total(_ items: [Expense]) -> Decimal {
        items.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private func newItem(_ kind: Expense.Kind) -> Expense {
        var item = Expense(kind: kind)
        // Default to today when viewing this month, otherwise the shown month.
        if let interval = Calendar.current.dateInterval(of: .month, for: month), !interval.contains(Date()) {
            item.date = interval.start
        }
        return item
    }

    private func shiftMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: month) {
            month = next
        }
    }
}

private struct ExpenseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var expense: Expense
    let currency: String

    init(expense: Expense, currency: String) {
        _expense = State(initialValue: expense)
        self.currency = currency
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $expense.kind) {
                        ForEach(Expense.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Amount", value: $expense.amount, format: .currency(code: currency))
                        .keyboardType(.decimalPad)
                        .font(.title2)
                    TextField("Title", text: $expense.title)
                }
                Section {
                    Picker("Category", selection: $expense.category) {
                        ForEach(Expense.Category.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    DatePicker("Date", selection: $expense.date, displayedComponents: .date)
                    TextField("Note", text: $expense.note, axis: .vertical)
                }
            }
            .navigationTitle(workspace.expenses.contains { $0.id == expense.id } ? "Edit" : "New \(expense.kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workspace.save(expense)
                        dismiss()
                    }
                    .disabled(expense.amount <= 0)
                }
            }
        }
    }
}

private struct BudgetSettings: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var budget: Decimal = 0
    @State private var currency = ""

    private static let currencies = ["USD", "EUR", "GBP", "SAR", "AED", "JOD", "EGP", "KWD", "QAR", "TRY", "SYP", "LBP", "IQD"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Budget") {
                    TextField("Budget", value: $budget, format: .currency(code: currency.isEmpty ? workspace.currencyCode : currency))
                        .keyboardType(.decimalPad)
                    Text("Set to 0 for no budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach(Array(Set(Self.currencies + [workspace.currencyCode])).sorted(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                }
            }
            .navigationTitle("Budget & Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workspace.setCurrency(currency)
                        workspace.setMonthlyBudget(budget)
                        dismiss()
                    }
                }
            }
            .onAppear {
                budget = workspace.monthlyBudget ?? 0
                currency = workspace.currencyCode
            }
        }
    }
}
