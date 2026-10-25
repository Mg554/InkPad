import GameController
import ObjectiveC
import UIKit

/// Decides, for every text field and text view in InkPad, whether Apple
/// Pencil writes into it (Scribble) or taps on it open the keyboard like a
/// finger, following `TextInputMode`.
///
/// SwiftUI text fields can't take a `UIScribbleInteraction` directly, so
/// one is added to each `UITextField` and `UITextView` when it appears.
@MainActor
final class ScribbleGate: NSObject, UIScribbleInteractionDelegate {
    static let shared = ScribbleGate()
    private static var isInstalled = false

    /// Call once when the app starts.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        swizzleDidMoveToWindow(of: UITextField.self, with: #selector(UITextField.inkpad_textFieldDidMoveToWindow))
        swizzleDidMoveToWindow(of: UITextView.self, with: #selector(UITextView.inkpad_textViewDidMoveToWindow))
        KeyboardWatcher.shared.start()
    }

    /// Runs `replacement` (which calls the original) whenever a view of this
    /// class moves to a window. Only this class is changed, not `UIView`.
    private static func swizzleDidMoveToWindow(of cls: AnyClass, with replacement: Selector) {
        let originalSelector = #selector(UIView.didMoveToWindow)
        guard let original = class_getInstanceMethod(cls, originalSelector),
              let swizzled = class_getInstanceMethod(cls, replacement)
        else { return }
        if class_addMethod(cls, originalSelector, method_getImplementation(swizzled), method_getTypeEncoding(swizzled)) {
            class_replaceMethod(cls, replacement, method_getImplementation(original), method_getTypeEncoding(original))
        } else {
            method_exchangeImplementations(original, swizzled)
        }
    }

    static func attach(to view: UIView) {
        guard view.window != nil else { return }
        let hasGate = view.interactions.contains { interaction in
            (interaction as? UIScribbleInteraction)?.delegate === shared
        }
        if !hasGate {
            view.addInteraction(UIScribbleInteraction(delegate: shared))
        }
    }

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        TextInputMode.current == .pencil
    }
}

extension UITextField {
    @objc dynamic func inkpad_textFieldDidMoveToWindow() {
        // After the swap this name runs the original `didMoveToWindow`.
        inkpad_textFieldDidMoveToWindow()
        ScribbleGate.attach(to: self)
    }
}

extension UITextView {
    @objc dynamic func inkpad_textViewDidMoveToWindow() {
        inkpad_textViewDidMoveToWindow()
        ScribbleGate.attach(to: self)
    }
}

/// Whether the on-screen keyboard is showing (the small shortcut bar shown
/// with a hardware keyboard doesn't count).
@MainActor
final class KeyboardWatcher: NSObject {
    static let shared = KeyboardWatcher()
    private(set) var isKeyboardVisible = false
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        isKeyboardVisible = frame.height > 150
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
    }
}

/// Explains why iPadOS didn't show the keyboard.
@MainActor
enum KeyboardHelp {
    static var hasHardwareKeyboard: Bool {
        GCKeyboard.coalesced != nil
    }

    /// Checks shortly after asking for the keyboard; calls `report` with the
    /// likely reason when it still isn't showing.
    static func checkAfterShowing(_ report: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !KeyboardWatcher.shared.isKeyboardVisible else { return }
            if hasHardwareKeyboard {
                report("A keyboard is connected to this iPad (Bluetooth, Smart Keyboard, Magic Keyboard or a keyboard case), so iPadOS doesn't show the on-screen keyboard. Type on that keyboard, or turn it off or disconnect it in Settings › Bluetooth to get the on-screen keyboard.")
            } else if UIScribbleInteraction.isPencilInputExpected {
                report("This was tapped with Apple Pencil. With Scribble on, iPadOS keeps the keyboard hidden after Apple Pencil taps and waits for handwriting. Tap the text field (or this button) with your finger to type, or turn off Settings › Apple Pencil › Scribble.")
            } else {
                report("iPadOS didn't show the keyboard. Tap the text field with your finger, or turn off Settings › Apple Pencil › Scribble so that taps with Apple Pencil open the keyboard too.")
            }
        }
    }
}
