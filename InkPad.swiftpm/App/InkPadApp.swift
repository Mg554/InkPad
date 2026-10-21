import SwiftUI

@main
struct InkPadApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var palette = ToolPalette()
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(palette)
                .environmentObject(workspace)
        }
    }
}
