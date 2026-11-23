import SwiftUI

/// A small shield on AI sheets showing this note's firewall level, so the
/// privacy decision is visible where the AI is actually used.
struct AIFirewallBadge: View {
    @EnvironmentObject private var store: LibraryStore
    let noteID: UUID

    private var access: AIAccess { store.aiAccess(of: noteID) }

    var body: some View {
        Label(tr(access.title), systemImage: access.systemImage)
            .font(.caption)
            .foregroundStyle(access == .never ? Color.red : access == .onDeviceOnly ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}
