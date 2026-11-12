import SwiftUI

/// What a pencil double tap or a finger tap does on the page.
enum GestureAction: String, Codable, CaseIterable, Identifiable {
    /// Apple Pencil only: follow the system's double-tap setting.
    case system
    case none
    case undo, redo
    case toggleEraser, previousTool, toggleLasso, toggleHighlighter
    case toggleToolbar, readingMode
    case commandPalette, addSticky, nextPage, previousPage

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System Setting"
        case .none: "Nothing"
        case .undo: "Undo"
        case .redo: "Redo"
        case .toggleEraser: "Eraser ↔ Pen"
        case .previousTool: "Previous Tool"
        case .toggleLasso: "Lasso ↔ Pen"
        case .toggleHighlighter: "Highlighter ↔ Pen"
        case .toggleToolbar: "Show or Hide Toolbar"
        case .readingMode: "Reading Mode"
        case .commandPalette: "Command Anywhere (⌘K)"
        case .addSticky: "Add a Sticky Note"
        case .nextPage: "Next Page"
        case .previousPage: "Previous Page"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "gear"
        case .none: "nosign"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .toggleEraser: "eraser"
        case .previousTool: "arrow.left.arrow.right"
        case .toggleLasso: "lasso"
        case .toggleHighlighter: "highlighter"
        case .toggleToolbar: "eye.slash"
        case .readingMode: "book"
        case .commandPalette: "command"
        case .addSticky: "note.text.badge.plus"
        case .nextPage: "chevron.down"
        case .previousPage: "chevron.up"
        }
    }

    /// Actions handled by the note editor rather than the canvas.
    var isEditorAction: Bool {
        switch self {
        case .toggleToolbar, .readingMode, .commandPalette, .addSticky: true
        default: false
        }
    }
}

/// The gestures that can be given an action.
enum GestureTrigger: String, Codable, CaseIterable, Identifiable {
    case pencilDoubleTap, twoFingerTap, threeFingerTap

    var id: Self { self }

    var title: String {
        switch self {
        case .pencilDoubleTap: "Apple Pencil Double Tap"
        case .twoFingerTap: "Two-Finger Tap"
        case .threeFingerTap: "Three-Finger Tap"
        }
    }

    var systemImage: String {
        switch self {
        case .pencilDoubleTap: "applepencil.tip"
        case .twoFingerTap: "hand.tap"
        case .threeFingerTap: "hand.raised"
        }
    }

    var defaultAction: GestureAction {
        switch self {
        case .pencilDoubleTap: .system
        case .twoFingerTap: .undo
        case .threeFingerTap: .redo
        }
    }

    var choices: [GestureAction] {
        let all = GestureAction.allCases
        return self == .pencilDoubleTap ? all : all.filter { $0 != .system }
    }
}

/// The owner's choice for each gesture, remembered between launches.
@MainActor
final class GestureSettingsStore: ObservableObject {
    static let shared = GestureSettingsStore()
    private static let defaultsKey = "gestureActions"

    @Published private(set) var actions: [GestureTrigger: GestureAction] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            var loaded: [GestureTrigger: GestureAction] = [:]
            for (key, value) in saved {
                if let trigger = GestureTrigger(rawValue: key), let action = GestureAction(rawValue: value) {
                    loaded[trigger] = action
                }
            }
            actions = loaded
        }
    }

    func action(for trigger: GestureTrigger) -> GestureAction {
        actions[trigger] ?? trigger.defaultAction
    }

    func set(_ action: GestureAction, for trigger: GestureTrigger) {
        actions[trigger] = action
        save()
    }

    func reset() {
        actions = [:]
        save()
    }

    private func save() {
        var raw: [String: String] = [:]
        for (trigger, action) in actions { raw[trigger.rawValue] = action.rawValue }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Settings › Gestures: pick what each gesture does.
struct GestureSettingsView: View {
    @ObservedObject private var store = GestureSettingsStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(GestureTrigger.allCases) { trigger in
                    Picker(selection: Binding(
                        get: { store.action(for: trigger) },
                        set: { store.set($0, for: trigger) }
                    )) {
                        ForEach(trigger.choices) { action in
                            Label(tr(action.title), systemImage: action.systemImage).tag(action)
                        }
                    } label: {
                        Label(tr(trigger.title), systemImage: trigger.systemImage)
                    }
                }
            } footer: {
                Text("Pinching to zoom and scrolling with fingers always stay the same. Double tap works with Apple Pencil (2nd generation and Pro).")
            }
            Section {
                Button("Reset to Default", role: .destructive) { store.reset() }
            }
        }
        .navigationTitle("Gestures")
        .navigationBarTitleDisplayMode(.inline)
    }
}
