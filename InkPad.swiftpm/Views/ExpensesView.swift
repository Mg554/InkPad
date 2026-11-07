import Charts
import SwiftUI

/// Notion-style budget tracker: monthly totals, a budget, spending by
/// category, and the month's transactions.
struct ExpensesView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var editing: Expense?
    @State private var isEditingSettings = false
    /// Where the finger is on the ring while touching (`nil` after lifting).
    @State private var selectedAmount: Double?
    /// The picked category; stays picked after the finger lifts.
    @State private var pickedCategory: Expense.Category?
    @State private var look = ExpenseLook.load()
    @State private var isCustomizing = false

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
            Group {
            Section {
                monthPicker
                summary
                if let budget = workspace.monthlyBudget {
                    budgetBar(budget)
                }
            }

            if look.showsRings && !monthItems.isEmpty {
                Section("This Month") {
                    BudgetRings(rings: rings, look: look)
                }
            }

            if !monthItems.filter({ $0.kind == .expense }).isEmpty {
                if look.showsDonut {
                    Section("Spending by Category") {
                        categoryChart
                    }
                }
                if look.showsBars {
                    Section("Category Bars") {
                        categoryBars
                    }
                }
                if look.showsDaily {
                    Section("Day by Day") {
                        dailyChart
                    }
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
            .listRowBackground(look.rowBackground)
        }
        .environment(\.colorScheme, look.colorScheme ?? systemScheme)
        .fontDesign(look.fontDesign)
        .animation(.snappy, value: look)
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
        .screenBackdrop(look.backdrop)
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isCustomizing = true
                } label: {
                    Label("Customize", systemImage: "paintbrush")
                }
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
        .sheet(isPresented: $isCustomizing) {
            ExpenseStyleView(look: $look)
        }
        .onChange(of: look) { look.save() }
    }

    @Environment(\.colorScheme) private var systemScheme

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
        .glowCard(color, isActive: false)
        .styledGlow(look.activeGlow, color: color)
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
                .styledGlow(look.activeGlow, color: tint)
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
        let selected = pickedCategory.flatMap { category in totals.contains { $0.0 == category } ? category : nil }
        return HStack(spacing: 24) {
            Chart(totals, id: \.0) { item in
                SectorMark(
                    angle: .value("Amount", item.1),
                    innerRadius: .ratio(selected == item.0 ? 0.55 : 0.62),
                    outerRadius: .ratio(selected == item.0 ? 1 : 0.92),
                    angularInset: 1.5
                )
                .cornerRadius(look.style == .paper ? 1 : 4)
                .foregroundStyle(look.fill(look.color(item.0)))
                .opacity(selected == nil || selected == item.0 ? 1 : 0.4)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAmount)
            .onChange(of: selectedAmount) {
                // Touching a slice picks it, and it stays picked after lifting.
                if let category = category(at: selectedAmount, in: totals) {
                    pickedCategory = category
                }
            }
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
            .styledGlow(look.activeGlow, color: look.color(selected ?? totals.first?.0 ?? .other))
            .overlay {
                if look.style == .glass {
                    // A light sheen across the glass ring.
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center))
                        .frame(width: 200, height: 200)
                        .allowsHitTesting(false)
                }
            }
            .animation(.snappy, value: selected)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(totals, id: \.0) { item in
                    // Tapping a row picks its slice; tapping the picked row shows the total again.
                    Button {
                        pickedCategory = pickedCategory == item.0 ? nil : item.0
                    } label: {
                        HStack {
                            Label(item.0.title, systemImage: item.0.systemImage)
                                .foregroundStyle(look.color(item.0))
                                .symbolEffect(.bounce, value: selected == item.0)
                            Spacer()
                            Text(money.string(item.1))
                                .foregroundStyle(selected == item.0 ? Color.primary : Color.secondary)
                        }
                        .font(.subheadline)
                        .fontWeight(selected == item.0 ? .bold : .regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(selected == item.0 ? Color.inkAccent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PressableStyle())
                }
                if selected != nil {
                    Button("Show Total") { pickedCategory = nil }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func row(_ item: Expense) -> some View {
        let tint: Color = item.kind == .income ? .green : look.color(item.category)
        return HStack(spacing: 12) {
            Image(systemName: item.category.systemImage)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: Circle())
                .styledGlow(look.activeGlow, color: tint)
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

    private var categoryTotals: [(Expense.Category, Double)] {
        Expense.Category.allCases.compactMap { category in
            let sum = total(monthItems.filter { $0.kind == .expense && $0.category == category })
            return sum > 0 ? (category, NSDecimalNumber(decimal: sum).doubleValue) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    private var categoryBars: some View {
        Chart(categoryTotals, id: \.0) { item in
            BarMark(
                x: .value("Category", item.0.title),
                y: .value("Amount", item.1),
                width: .ratio(0.6)
            )
            .cornerRadius(look.style == .paper ? 1 : 6)
            .foregroundStyle(look.fill(look.color(item.0)))
            .annotation(position: .top) {
                Text(money.string(item.1))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 220)
        .styledGlow(look.activeGlow, color: look.color(categoryTotals.first?.0 ?? .other))
        .padding(.vertical, 8)
    }

    /// Spending added up day by day, with the budget's even pace.
    private var dailyChart: some View {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: month)
        let dayCount = interval.flatMap { calendar.range(of: .day, in: .month, for: $0.start)?.count } ?? 30
        let isThisMonth = interval?.contains(Date()) ?? false
        let lastDay = isThisMonth ? calendar.component(.day, from: Date()) : dayCount
        var running = 0.0
        let points: [(Int, Double)] = (1...max(lastDay, 1)).map { day in
            let spentThatDay = monthItems
                .filter { $0.kind == .expense && calendar.component(.day, from: $0.date) == day }
                .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.amount).doubleValue }
            running += spentThatDay
            return (day, running)
        }
        let budget = workspace.monthlyBudget.map { NSDecimalNumber(decimal: $0).doubleValue }
        let lineColor = look.style == .minimal ? Color.inkAccent : look.style == .paper ? Color(red: 0.3, green: 0.42, blue: 0.55) : look.style == .neon ? Color(red: 0.2, green: 0.8, blue: 1) : Color.inkAccent
        return Chart {
            ForEach(points, id: \.0) { point in
                AreaMark(x: .value("Day", point.0), y: .value("Spent", point.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [lineColor.opacity(look.style == .paper ? 0.15 : 0.35), lineColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", point.0), y: .value("Spent", point.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: look.style == .neon ? 3 : 2.5, lineCap: .round))
            }
            if let budget, budget > 0 {
                ForEach([1, dayCount], id: \.self) { day in
                    LineMark(x: .value("Day", day), y: .value("Spent", budget * Double(day) / Double(dayCount)), series: .value("Line", "Budget pace"))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
            }
        }
        .chartXScale(domain: 1...dayCount)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(money.string(amount)) }
                }
            }
        }
        .frame(height: 200)
        .styledGlow(look.activeGlow, color: lineColor)
        .padding(.vertical, 8)
        .overlay(alignment: .topLeading) {
            if budget != nil {
                Label("Budget pace", systemImage: "line.diagonal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rings: [BudgetRings.Ring] {
        let spentValue = NSDecimalNumber(decimal: spent).doubleValue
        let earnedValue = NSDecimalNumber(decimal: earned).doubleValue
        var rings: [BudgetRings.Ring] = []
        if let budget = workspace.monthlyBudget, budget > 0 {
            let budgetValue = NSDecimalNumber(decimal: budget).doubleValue
            rings.append(.init(id: "budget", title: "Budget Used", value: spentValue / budgetValue,
                               detail: "\(Int((spentValue / budgetValue * 100).rounded()))%",
                               color: spentValue > budgetValue ? .red : look.style == .paper ? Color(red: 0.65, green: 0.22, blue: 0.18) : Color(red: 1, green: 0.2, blue: 0.4)))
        }
        if earnedValue > 0 {
            let kept = max(earnedValue - spentValue, 0) / earnedValue
            rings.append(.init(id: "kept", title: "Income Kept", value: kept, detail: "\(Int((kept * 100).rounded()))%",
                               color: look.style == .paper ? Color(red: 0.42, green: 0.52, blue: 0.25) : Color(red: 0.4, green: 0.95, blue: 0.2)))
        }
        let calendar = Calendar.current
        if let interval = calendar.dateInterval(of: .month, for: month) {
            let days = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
            let passed = interval.contains(Date()) ? calendar.component(.day, from: Date()) : (interval.end < Date() ? days : 0)
            rings.append(.init(id: "month", title: "Month Passed", value: Double(passed) / Double(days), detail: "\(passed) of \(days) days",
                               color: look.style == .paper ? Color(red: 0.3, green: 0.42, blue: 0.55) : Color(red: 0.2, green: 0.85, blue: 1)))
        }
        return rings
    }

    // MARK: Helpers

    private var days: [Date] {
        let starts = monthItems.map { Calendar.current.startOfDay(for: $0.date) }
        return Array(Set(starts)).sorted(by: >)
    }

    /// The category under the chart selection (which reports an amount along the ring).
    private func category(at selectedAmount: Double?, in totals: [(Expense.Category, Double)]) -> Expense.Category? {
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
