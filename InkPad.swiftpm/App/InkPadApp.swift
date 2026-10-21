import SwiftUI

@main
struct InkPadApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var palette = ToolPalette()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(palette)
        }
    }
}
