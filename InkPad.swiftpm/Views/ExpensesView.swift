import Charts
import SwiftUI

/// Notion-style budget tracker: monthly totals, a budget, spending by
/// category, and the month's transactions.
struct ExpensesView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var editing: Expense?
    @State private var isEditingSettings = false
    @State private var selectedAmount: Double?
    @State private var glowPhase = false

    private var currency: String { workspace.currencyCode }
    private var money: MoneyFormatter { workspace.money }

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
            Text(money.string(value))
                .font(.title3.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glowCard(color, isActive: glowPhase || title != "Balance")
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glowPhase)
        .onAppear { glowPhase = true }
    }

    private func budgetBar(_ budget: Decimal) -> some View {
        let used = budget > 0 ? min(NSDecimalNumber(decimal: spent / budget).doubleValue, 1.5) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Budget")
                Spacer()
                Text("\(money.string(spent)) of \(money.string(budget))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            let tint: Color = used < 0.8 ? .green : used < 1 ? .orange : .red
            ProgressView(value: min(used, 1))
                .tint(tint)
                .shadow(color: tint.opacity(0.7), radius: 6)
                .animation(.snappy, value: used)
            if used >= 1 {
                Text("Over budget by \(money.string(spent - budget))")
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
        let selected = selectedCategory(in: totals)
        return HStack(spacing: 24) {
            Chart(totals, id: \.0) { item in
                SectorMark(
                    angle: .value("Amount", item.1),
                    innerRadius: .ratio(selected == item.0 ? 0.55 : 0.62),
                    outerRadius: .ratio(selected == item.0 ? 1 : 0.92),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Category", item.0.title))
                .opacity(selected == nil || selected == item.0 ? 1 : 0.4)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAmount)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(selected?.title ?? "Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(money.string(selected.flatMap { category in totals.first { $0.0 == category }?.1 } ?? NSDecimalNumber(decimal: spent).doubleValue))
                        .font(.headline)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 200, height: 200)
            .shadow(color: .accentColor.opacity(0.25), radius: 14)
            .animation(.snappy, value: selected)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(totals, id: \.0) { item in
                    HStack {
                        Label(item.0.title, systemImage: item.0.systemImage)
                            .symbolEffect(.bounce, value: selected == item.0)
                        Spacer()
                        Text(money.string(item.1))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .fontWeight(selected == item.0 ? .bold : .regular)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func row(_ item: Expense) -> some View {
        let tint: Color = item.kind == .income ? .green : .accentColor
        return HStack(spacing: 12) {
            Image(systemName: item.category.systemImage)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: Circle())
                .shadow(color: tint.opacity(0.5), radius: 6)
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
            Text(money.string(item.kind == .income ? item.amount : -item.amount))
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

    /// The category under the chart selection (which reports an amount along the ring).
    private func selectedCategory(in totals: [(Expense.Category, Double)]) -> Expense.Category? {
        guard let selectedAmount else { return nil }
        var running = 0.0
        for (category, amount) in totals {
            running += amount
            if selectedAmount <= running { return category }
        }
        return nil
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
                    HStack {
                        Text(currency)
                            .foregroundStyle(.secondary)
                        TextField("Amount", value: $expense.amount, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                    }
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
    @State private var showsCents = false

    private static let currencies = ["USD", "EUR", "GBP", "ILS", "SAR", "AED", "JOD", "EGP", "KWD", "QAR", "TRY", "SYP", "LBP", "IQD"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Budget") {
                    TextField("Budget", value: $budget, format: .number)
                        .keyboardType(.decimalPad)
                    Text("Set to 0 for no budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Numbers") {
                    Toggle("Always Show Decimals (1,000.00)", isOn: $showsCents)
                    Text(showsCents ? "Amounts always show two decimals." : "Whole amounts show without decimals, like 1,000.")
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
                        workspace.setShowsCents(showsCents)
                        dismiss()
                    }
                }
            }
            .onAppear {
                budget = workspace.monthlyBudget ?? 0
                currency = workspace.currencyCode
                showsCents = workspace.showsCents
            }
        }
    }
}
