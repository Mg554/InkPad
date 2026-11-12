import SwiftUI

@main
struct InkPadApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var palette = ToolPalette()
    @StateObject private var workspace = WorkspaceStore()
    @ObservedObject private var theme = ThemeSettings.shared
    @ObservedObject private var language = LanguageSettings.shared
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ScribbleGate.install()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                // A theme change rebuilds the views, so every color and
                // font picks it up.
                .id("\(theme.revision)-\(language.revision)")
                .environment(\.locale, language.language.locale)
                .environment(\.layoutDirection, language.language.layoutDirection)
                .tint(theme.recipe.accent)
                .fontDesign(theme.recipe.appFont.design)
                .environmentObject(store)
                .environmentObject(palette)
                .environmentObject(workspace)
                .preferredColorScheme(appearance.colorScheme)
                // Automatic backups run when InkPad opens or comes back.
                .task {
                    SyncEngine.shared.start(store: store, workspace: workspace)
                    SyncEngine.shared.soon(delay: 3)
                    await store.makeAutomaticBackupIfDue()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task { await store.makeAutomaticBackupIfDue() }
                        SyncEngine.shared.soon(delay: 2)
                    } else if scenePhase == .background {
                        // Notes are saved on the way out; send them.
                        SyncEngine.shared.soon(delay: 1)
                    }
                }
        }
    }
}
