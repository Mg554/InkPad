import SwiftUI

@main
struct InkPadApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var palette = ToolPalette()
    @StateObject private var workspace = WorkspaceStore()
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ScribbleGate.install()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(palette)
                .environmentObject(workspace)
                .preferredColorScheme(appearance.colorScheme)
                // Automatic backups run when InkPad opens or comes back.
                .task { await store.makeAutomaticBackupIfDue() }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task { await store.makeAutomaticBackupIfDue() }
                    }
                }
        }
    }
}
