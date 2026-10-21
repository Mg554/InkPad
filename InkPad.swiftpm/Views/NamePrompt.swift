import SwiftUI

/// A request to ask the user for a name (new folder, rename, ...).
struct NamePrompt: Identifiable {
    let id = UUID()
    let title: String
    let initialText: String
    let confirmTitle: String
    let onConfirm: (String) -> Void
}

private struct NamePromptModifier: ViewModifier {
    @Binding var prompt: NamePrompt?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(
                prompt?.title ?? "",
                isPresented: Binding(
                    get: { prompt != nil },
                    set: { if !$0 { prompt = nil } }
                ),
                presenting: prompt
            ) { current in
                TextField("Name", text: $text)
                Button("Cancel", role: .cancel) {}
                Button(current.confirmTitle) { current.onConfirm(text) }
            }
            .onChange(of: prompt?.id) {
                text = prompt?.initialText ?? ""
            }
    }
}

extension View {
    func namePrompt(_ prompt: Binding<NamePrompt?>) -> some View {
        modifier(NamePromptModifier(prompt: prompt))
    }
}
