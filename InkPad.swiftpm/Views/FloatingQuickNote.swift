import SwiftUI

/// Shared state for the in-app floating Quick Note. The note stays on screen
/// while the owner moves between notes, and its draft survives a close.
@MainActor
final class FloatingQuickNoteCenter: ObservableObject {
    static let shared = FloatingQuickNoteCenter()

    @Published var isShown = false
    @Published var opacity: Double = UserDefaults.standard.object(forKey: "floatingQuickNoteOpacity") as? Double ?? 0.96 {
        didSet { UserDefaults.standard.set(opacity, forKey: "floatingQuickNoteOpacity") }
    }
    @Published var draft: String = UserDefaults.standard.string(forKey: "floatingQuickNoteDraft") ?? "" {
        didSet { UserDefaults.standard.set(draft, forKey: "floatingQuickNoteDraft") }
    }

    func toggle() {
        withAnimation(.snappy) { isShown.toggle() }
    }
}

/// A small draggable button that opens the Quick Note. It lives on the left
/// so it never covers the Command Anywhere button on the right.
struct FloatingQuickNoteButton: View {
    @ObservedObject private var center = FloatingQuickNoteCenter.shared

    var body: some View {
        FloatingPlacement(key: "quickNoteButton.library", x: 0.06, y: 0.82) {
            Image(systemName: center.isShown ? "note.text.badge.plus" : "note.text")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.inkAccent.gradient, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                .shadow(color: Color.inkAccent.opacity(0.45), radius: 9)
                .opacity(0.9)
                .contentShape(Circle())
                .onTapGesture { center.toggle() }
                .accessibilityLabel(tr("Floating Quick Note"))
                .accessibilityHint(tr("Write a thought without leaving the library"))
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// The panel itself. Everything is saved locally: words go to the daily
/// note through the same path as Quick Capture, and nothing leaves the iPad.
struct FloatingQuickNotePanel: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var center = FloatingQuickNoteCenter.shared

    @State private var message = ""
    @State private var drag: CGSize = .zero
    @State private var placed: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            panel
                .frame(width: min(360, geometry.size.width - 32))
                .position(notePosition(in: geometry))
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            drag = CGSize(
                                width: placed.width + value.translation.width,
                                height: placed.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            placed = CGSize(
                                width: placed.width + value.translation.width,
                                height: placed.height + value.translation.height
                            )
                            drag = placed
                        }
                )
        }
        .opacity(center.opacity)
    }

    private func notePosition(in geometry: GeometryProxy) -> CGPoint {
        let width = max(geometry.size.width, 1)
        let height = max(geometry.size.height, 1)
        let x = min(max(width * 0.5 + drag.width, 190), width - 190)
        let y = min(max(height * 0.42 + drag.height, 150), height - 210)
        return CGPoint(x: x, y: y)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TextEditor(text: $center.draft)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.inkAccent)
            }
            opacityRow
            actions
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.inkAccent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }

    private var header: some View {
        HStack {
            Label(tr("Quick Note"), systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(Color.inkAccent)
            Spacer()
            Button {
                center.toggle()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Close"))
        }
    }

    private var opacityRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $center.opacity, in: 0.55...1)
                .tint(Color.inkAccent)
        }
    }

    private var actions: some View {
        HStack {
            Button(tr("Clear")) {
                center.draft = ""
                message = ""
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                save()
            } label: {
                Label(tr("Save to Today"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkAccent)
            .disabled(center.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func save() {
        let words = center.draft
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = QuickCapture.dailyNote(in: store) ?? store.createTextNote(titled: "Daily Note", in: nil)
        guard let id = note?.id else { return }
        if QuickCapture.append(words, to: id, store: store) {
            center.draft = ""
            message = tr("Added to Today's Note.")
        } else {
            message = tr("Nothing was added.")
        }
    }
}

/// Adds the floating note to the library without lengthening LibraryView's
/// modifier chain (Swift Playgrounds type-checks long chains slowly).
struct FloatingQuickNoteLayer: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var center = FloatingQuickNoteCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay { FloatingQuickNoteButton() }
            .overlay {
                if center.isShown {
                    FloatingQuickNotePanel()
                        .environmentObject(store)
                }
            }
    }
}
