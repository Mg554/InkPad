import Foundation
import UserNotifications

/// The Flowmodoro break-end notification, only in the installed app.
/// `UNUserNotificationCenter` crashes apps run inside Swift Playgrounds, so
/// every entry point checks first and does nothing there.
enum FlowNotifications {
    private static let identifier = "InkPad.Flowmodoro.BreakEnd"

    static var isPlaygrounds: Bool {
        Bundle.main.bundlePath.contains("Playground")
            || (Bundle.main.bundleIdentifier ?? "").contains("swift-playgrounds")
    }

    private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    static func requestPermissionIfNeeded() async {
        guard !isPlaygrounds else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Fires when the earned break is over. Uses a time interval so it still
    /// works if the iPad is locked while the break runs.
    static func scheduleBreak(seconds: Int, task: String) async {
        guard !isPlaygrounds, seconds > 0 else { return }
        await requestPermissionIfNeeded()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("Break Over")
        let pattern = trMessage("Your {} break is done. Ready for the next focus session?")
        content.body = pattern.replacingOccurrences(of: "{}", with: task)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Called when a break is skipped or ended early.
    static func cancelBreak() {
        guard !isPlaygrounds else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
