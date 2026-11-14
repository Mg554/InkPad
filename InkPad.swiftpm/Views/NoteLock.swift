import LocalAuthentication
import SwiftUI

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

/// Safety net for locked notes: wherever a note opens through navigation,
/// this shows a lock screen instead of the note's contents until the note
/// is unlocked with Face ID (or the passcode).
struct NoteLockGate<Content: View>: View {
    @EnvironmentObject private var store: LibraryStore
    let noteID: UUID
    @ViewBuilder let content: () -> Content
    @State private var isAuthenticating = false

    private var title: String { store.note(noteID)?.title ?? "" }

    var body: some View {
        if store.isUnlocked(noteID) {
            content()
        } else {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(tr("Note Locked"))
                    .font(.headline)
                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    authenticate()
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let outcome = await NoteLock.authenticate(reason: trMessage("Unlock \(title)."))
            switch outcome {
            case .unlocked:
                store.unlockNote(noteID)
            case .failed:
                CommandCenter.shared.say("Locked notes open with Face ID or the passcode.")
            case .needsPasscode:
                CommandCenter.shared.say("Set a passcode on this iPad — locked notes open with Face ID or the passcode.")
            }
            isAuthenticating = false
        }
    }
}
