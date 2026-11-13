import LocalAuthentication

/// Face ID (with the device passcode as the fallback) for locked notes.
/// Without a device passcode there is nothing to fall back to, so locked
/// notes stay closed and the app asks for one.
@MainActor
enum NoteLock {
    enum Outcome {
        /// The owner proved themself.
        case unlocked
        /// Face ID or the passcode was declined or failed.
        case failed
        /// No device passcode is set, so authentication is impossible here.
        case needsPasscode
    }

    /// Runs the system authentication dialog; does not decide anything else.
    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .needsPasscode
        }
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                return .unlocked
            }
            return .failed
        } catch {
            return .failed
        }
    }
}
