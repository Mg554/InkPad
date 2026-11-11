import SwiftUI

/// One subject's plant in the Focus Garden.
struct GardenPlant: Identifiable {
    var id: String { subject }
    let subject: String
    let seconds: Int

    /// Minutes at which each stage starts.
    static let stages: [(minutes: Int, name: String)] = [
        (0, "Seed"), (15, "Sprout"), (60, "Seedling"), (180, "Sapling"), (600, "Young Tree"), (1500, "Tree"), (3000, "Grand Tree"),
    ]

    var minutes: Int { seconds / 60 }

    var stage: Int {
        let found: Int? = Self.stages.lastIndex(where: { minutes >= $0.minutes })
        return found ?? 0
    }

    var stageName: String { Self.stages[stage].name }

    /// 0...1 over all stages, for drawing.
    var growth: Double {
        let index = stage
        guard index < Self.stages.count - 1 else { return 1 }
        let start = Double(Self.stages[index].minutes)
        let end = Double(Self.stages[index + 1].minutes)
        let within: Double = (Double(minutes) - start) / max(end - start, 1)
        return (Double(index) + within) / Double(Self.stages.count - 1)
    }

    var minutesToNext: Int? {
        let index = stage
        guard index < Self.stages.count - 1 else { return nil }
        return Self.stages[index + 1].minutes - minutes
    }

    /// Plants from Flowmodoro sessions: a planner task's first tag is its
    /// subject; otherwise the task's title.
    static func garden(sessions: [FlowSession], tasks: [PlanTask]) -> [GardenPlant] {
        var tagByTask: [UUID: String] = [:]
        for task in tasks {
            if let tag = task.tags.first { tagByTask[task.id] = tag }
        }
        var totals: [String: Int] = [:]
        for session in sessions {
            let tag: String? = session.planTaskID.flatMap { tagByTask[$0] }
            let subject = tag ?? session.taskTitle
            totals[subject, default: 0] += session.workSeconds
        }
        let plants = totals.map { GardenPlant(subject: $0.key, seconds: $0.value) }
        return plants.sorted { $0.seconds > $1.seconds }
    }
}

/// A plant card, drawn for the season.
struct GardenPlantCard: View {
    let plant: GardenPlant
    var size: CGFloat = 130

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, canvasSize in
                PlantPainter.draw(in: &context, size: canvasSize, growth: plant.growth, season: PlantPainter.currentSeason, tint: .green)
            }
            .frame(width: size, height: size)
            Text(plant.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(plant.stageName) · \(PlannerInsights.duration(plant.seconds))").font(.caption).foregroundStyle(.secondary)
            if let next = plant.minutesToNext {
                ProgressView(value: plant.growth)
                    .tint(.green)
                    .frame(width: size * 0.8)
                Text("\(next) min to grow").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: size + 30)
        .themedCard()
    }
}

/// Every subject's plant, growing with focus time.
struct FocusGardenView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plants = GardenPlant.garden(sessions: workspace.flowSessions, tasks: workspace.tasks)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Each subject grows a plant as you focus on it: a planner task's first tag is its subject. Plants dress for the season (\(PlantPainter.currentSeason.title)).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if plants.isEmpty {
                        ContentUnavailableView("Nothing Planted Yet", systemImage: "leaf", description: Text("Finish a Flowmodoro session to plant your first seed."))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        ForEach(plants) { plant in
                            GardenPlantCard(plant: plant, size: 140)
                        }
                    }
                }
                .padding(20)
            }
            .themedBackground()
            .navigationTitle("Focus Garden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: Smart breaks

/// What to do with a break: due flashcards, breathing, or moving.
struct SmartBreakCard: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var isReviewing = false
    @State private var isBreathing = false
    @State private var tip = SmartBreakCard.tips.randomElement() ?? SmartBreakCard.tips[0]

    static let tips: [(String, String)] = [
        ("figure.walk", "Walk for a few minutes; let your eyes rest on something far away."),
        ("drop", "Drink a glass of water."),
        ("figure.cooldown", "Stretch your neck, shoulders and back."),
        ("eye", "20-20-20: look at something 20 feet away for 20 seconds."),
        ("window.vertical.open", "Open a window and breathe fresh air."),
    ]

    private var dueCards: Int {
        workspace.flashcardDecks.reduce(0) { $0 + $1.dueCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Smart Break", systemImage: "sparkles").font(.headline)
            HStack(spacing: 10) {
                if dueCards > 0 {
                    option("rectangle.on.rectangle.angled", "\(dueCards) flashcards due", .purple) { isReviewing = true }
                }
                option("wind", "Breathe for a minute", .teal) { isBreathing = true }
                option(tip.0, "Move", .orange) {
                    tip = Self.tips.randomElement() ?? tip
                }
            }
            Text(tip.1).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .sheet(isPresented: $isReviewing) {
            NavigationStack {
                FlashcardReviewView(deckID: nil)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isReviewing = false }
                        }
                    }
            }
            .environmentObject(workspace)
        }
        .sheet(isPresented: $isBreathing) {
            BreathingView()
        }
    }

    private func option(_ icon: String, _ title: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(tr(title)).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Breathe in 4 s, hold 4 s, out 6 s, with a circle that grows and shrinks.
struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.distantFuture

    private static let steps: [(name: String, seconds: Double)] = [("Breathe in", 4), ("Hold", 4), ("Breathe out", 6)]

    var body: some View {
        NavigationStack {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let state = phase(at: timeline.date)
                VStack(spacing: 30) {
                    ZStack {
                        Circle().fill(Color.teal.opacity(0.15)).frame(width: 260, height: 260)
                        Circle()
                            .fill(Color.teal.gradient)
                            .frame(width: 260 * state.scale, height: 260 * state.scale)
                            .shadow(color: .teal.opacity(0.5), radius: 20)
                    }
                    Text(tr(state.name)).font(.title.weight(.semibold))
                    Text("Cycle \(state.cycle) of 5").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { start = Date() }
            .navigationTitle("Breathe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func phase(at date: Date) -> (name: String, scale: CGFloat, cycle: Int) {
        let total: Double = 14
        let elapsed: Double = max(date.timeIntervalSince(start), 0)
        let cycle = min(Int(elapsed / total) + 1, 5)
        guard elapsed < total * 5 else { return ("Well done", 0.55, 5) }
        var t: Double = elapsed.truncatingRemainder(dividingBy: total)
        let small: Double = 0.35
        if t < 4 { return ("Breathe in", CGFloat(small + (1 - small) * t / 4), cycle) }
        t -= 4
        if t < 4 { return ("Hold", 1, cycle) }
        t -= 4
        return ("Breathe out", CGFloat(1 - (1 - small) * t / 6), cycle)
    }
}
