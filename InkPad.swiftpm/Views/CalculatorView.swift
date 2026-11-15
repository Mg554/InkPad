import PencilKit
import SwiftUI
import UIKit

/// The calculator: write an equation with the pencil and it becomes
/// printed, worked out numbers — or use the scientific keys.
struct CalculatorView: View {
    /// Writing with the pencil, or the keys.
    enum Mode: String, CaseIterable, Identifiable {
        case writing, keys
        var id: Self { self }

        var title: String {
            switch self {
            case .writing: "Writing"
            case .keys: "Keys"
            }
        }

        var symbol: String {
            switch self {
            case .writing: "pencil.and.scribble"
            case .keys: "keyboard"
            }
        }
    }

    @State private var mode: Mode = .writing
    /// What the owner wrote or typed, as printed text.
    @State private var expression = ""
    /// The answer, as printed text.
    @State private var result: String?
    /// Why the expression could not be read.
    @State private var problem: String?
    /// The handwriting on the canvas.
    @State private var ink = PKDrawing()
    @State private var isReading = false

    var body: some View {
        VStack(spacing: 0) {
            display
            Divider()
            switch mode {
            case .writing:
                writingArea
            case .keys:
                keys
            }
        }
        .themedBackground()
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Display

    private var display: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.lg) {
            Picker(selection: $mode) {
                ForEach(Mode.allCases) { option in
                    Label(tr(option.title), systemImage: option.symbol).tag(option)
                }
            } label: {
                Text("Mode")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            TextField("Write or type an expression", text: $expression)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: expression) { evaluate(expression) }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
                Spacer()
                if let result {
                    Text(result)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.inkAccent)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = result
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy Result")
                }
            }

            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
    }

    // MARK: Writing

    private var writingArea: some View {
        VStack(spacing: Theme.Spacing.xl) {
            CalculatorCanvas(drawing: $ink)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
                .overlay {
                    if ink.strokes.isEmpty {
                        Text("Write your equation here")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: Theme.Spacing.xl) {
                Button {
                    clearAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer()

                if isReading {
                    ProgressView()
                }
                Button {
                    convert()
                } label: {
                    Label("Convert", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(ink.strokes.isEmpty || isReading)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
    }

    /// Reads the handwriting, turns it into printed text and works it out.
    private func convert() {
        let drawing = ink
        isReading = true
        Task {
            let picture = InkSnapshot.onWhite(of: drawing, from: drawing.bounds.insetBy(dx: -16, dy: -16), scale: 2)
            let text = await Task.detached(priority: .userInitiated) { () -> String in
                guard let cgImage = picture.cgImage else { return "" }
                return InkOCR.text(in: cgImage)
            }.value
            isReading = false
            let cleaned = MathExpression.normalized(text)
            expression = cleaned
            evaluate(cleaned)
            // The writing becomes printed text.
            ink = PKDrawing()
        }
    }

    private func clearAll() {
        ink = PKDrawing()
        expression = ""
        result = nil
        problem = nil
    }

    // MARK: Keys

    private var keys: some View {
        VStack(spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 6), spacing: Theme.Spacing.md) {
                ForEach(scientificKeys, id: \.self) { key in
                    keyButton(key, prominent: false)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4), spacing: Theme.Spacing.md) {
                ForEach(numberKeys, id: \.self) { key in
                    keyButton(key, prominent: key == "=")
                }
            }
        }
        .padding(20)
    }

    /// The scientific row: brackets, powers, roots and the functions.
    private let scientificKeys = ["(", ")", "%", "^", "!", "√", "sin(", "cos(", "tan(", "ln(", "log(", "π"]

    /// The numbers and the signs.
    private let numberKeys = [
        "AC", "⌫", "±", "÷",
        "7", "8", "9", "×",
        "4", "5", "6", "−",
        "1", "2", "3", "+",
        "0", ".", "=", "Ans",
    ]

    private func keyButton(_ key: String, prominent: Bool) -> some View {
        Button {
            press(key)
        } label: {
            Text(key)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        .fill(prominent ? Color.inkAccent : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    /// What a key does.
    private func press(_ key: String) {
        switch key {
        case "AC":
            clearAll()
            return
        case "⌫":
            if !expression.isEmpty { expression.removeLast() }
        case "=":
            evaluate(expression)
            return
        case "±":
            expression = expression.hasPrefix("-") ? String(expression.dropFirst()) : "-" + expression
        case "√":
            expression += "sqrt("
        case "π":
            expression += "pi"
        case "Ans":
            if let result { expression += result }
        default:
            expression += key
        }
        evaluate(expression)
    }

    // MARK: Working out

    /// Works the expression out and shows the answer, or why it cannot.
    private func evaluate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            result = nil
            problem = nil
            return
        }
        do {
            let value = try MathExpression.value(of: trimmed)
            result = MathExpression.format(value)
            problem = nil
        } catch let failure as MathExpression.Failure {
            result = nil
            problem = message(for: failure)
        } catch {
            result = nil
            problem = trMessage("The expression could not be read.")
        }
    }

    /// What went wrong, in the app's language.
    private func message(for failure: MathExpression.Failure) -> String {
        switch failure {
        case .empty:
            return trMessage("Write an expression first.")
        case .unfinished:
            return trMessage("The expression is not finished.")
        case .unexpected(let character):
            return trMessage("“\(character)” does not belong in an expression.")
        case .unclosedBracket:
            return trMessage("A bracket is not closed.")
        case .unknownName(let name):
            return trMessage("“\(name)” is not a known function.")
        case .divisionByZero:
            return trMessage("You cannot divide by zero.")
        case .outOfRange(_):
            return trMessage("That number is out of range for this function.")
        }
    }
}

/// The paper the owner writes the equation on.
struct CalculatorCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.drawingPolicy = .anyInput
        // The canvas writes with a pencil by default; the paper is white, so
        // the ink reads well.
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // The canvas owns the strokes while writing; only take them back
        // when something else changed them.
        if canvas.drawing.strokes.count != drawing.strokes.count {
            canvas.drawing = drawing
        }
        context.coordinator.drawing = $drawing
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
