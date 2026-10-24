import Foundation

/// Flowmodoro: work on one task for as long as you stay focused, stop when
/// you lose focus, then rest for a share of the time you worked. Based on
/// the Pythonation/flowmodoro-wep-app web app.
enum Flowmodoro {
    /// The shortest break, in seconds.
    static let minimumBreak = 60
    /// Break shares offered, in percent of the work time. 5% matches the
    /// web app; 20% (one fifth) is the classic Flowmodoro rule.
    static let breakShares = [5, 10, 15, 20]
    static let defaultBreakShare = 5

    static func breakSeconds(forWork seconds: Int, share: Int) -> Int {
        max(minimumBreak, Int((Double(seconds) * Double(share) / 100).rounded()))
    }

    /// "01:05:09", or "05:09" without hours unless `forceHours`.
    static func clock(_ totalSeconds: Int, forceHours: Bool = false) -> String {
        let seconds = max(totalSeconds, 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 || forceHours
            ? "\(two(hours)):\(two(minutes)):\(two(rest))"
            : "\(two(minutes)):\(two(rest))"
    }

    /// "1h 25m", "25m" or "40s".
    static func duration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(max(totalSeconds, 0))s"
    }
}

struct FlowTask: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    let createdAt: Date

    init(title: String) {
        id = UUID()
        self.title = title
        isDone = false
        createdAt = Date()
    }
}

/// One finished stretch of work and the break it earned.
struct FlowSession: Codable, Identifiable, Equatable {
    let id: UUID
    var taskTitle: String
    var workSeconds: Int
    var breakSeconds: Int
    let endedAt: Date
}

/// The timer in progress. Saved with its start times, so it keeps counting
/// while you are elsewhere in InkPad or the app is closed.
struct FlowTimer: Codable, Equatable {
    enum Phase: String, Codable {
        /// The work stopwatch is counting up.
        case working
        /// Work stopped; the break is waiting to start.
        case breakReady
        /// The break is counting down.
        case onBreak
    }

    var taskID: UUID
    var taskTitle: String
    var phase: Phase
    var workStartedAt: Date
    /// Set when work stops.
    var workSeconds: Int
    var breakSeconds: Int
    var breakStartedAt: Date?

    func workElapsed(at now: Date) -> Int {
        phase == .working ? max(0, Int(now.timeIntervalSince(workStartedAt))) : workSeconds
    }

    func breakRemaining(at now: Date) -> Int {
        guard phase == .onBreak, let breakStartedAt else { return breakSeconds }
        return max(0, breakSeconds - Int(now.timeIntervalSince(breakStartedAt)))
    }

    var breakEndsAt: Date? {
        breakStartedAt.map { $0.addingTimeInterval(TimeInterval(breakSeconds)) }
    }
}
