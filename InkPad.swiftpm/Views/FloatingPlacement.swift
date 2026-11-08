import SwiftUI

/// Places a floating button that can be dragged anywhere (finger or
/// Pencil). Its place is kept as a fraction of the space, under `key`, so
/// each place it lives in (the library, inside notes) remembers its own.
struct FloatingPlacement<Content: View>: View {
    @AppStorage private var x: Double
    @AppStorage private var y: Double
    @State private var drag: CGSize = .zero
    @State private var isDragging = false
    private let content: Content

    init(key: String, x: Double, y: Double, @ViewBuilder content: () -> Content) {
        _x = AppStorage(wrappedValue: x, "\(key).x")
        _y = AppStorage(wrappedValue: y, "\(key).y")
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .scaleEffect(isDragging ? 1.15 : 1)
                .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 12, y: 6)
                .position(
                    x: clamp(x) * geometry.size.width + drag.width,
                    y: clamp(y) * geometry.size.height + drag.height
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging {
                                withAnimation(.snappy) { isDragging = true }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { drag = value.translation }
                        }
                        .onEnded { value in
                            let width = max(geometry.size.width, 1)
                            let height = max(geometry.size.height, 1)
                            x = clamp((clamp(x) * width + value.translation.width) / width)
                            y = clamp((clamp(y) * height + value.translation.height) / height)
                            drag = .zero
                            withAnimation(.snappy) { isDragging = false }
                        }
                )
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0.04), 0.96)
    }
}
