import PencilKit
import UIKit
import UniformTypeIdentifiers

/// What can be dragged between two notes side by side.
enum CanvasDragType {
    /// PencilKit ink (also what Copy puts on the pasteboard).
    static let drawing = "com.apple.drawing"
    /// A sticky note, as JSON.
    static let sticky = "com.inkpad.sticky"
    /// Plain text payloads that are commands, not words: a note
    /// (`inkpad-note:<id>`) or a page (`inkpad-page:<note id>:<index>`).
    static let notePrefix = "inkpad-note:"
    static let pagePrefix = "inkpad-page:"

    static func notePayload(_ id: UUID) -> String { notePrefix + id.uuidString }
    static func pagePayload(note: UUID, page: Int) -> String { pagePrefix + note.uuidString + ":" + String(page) }

    static func noteID(in text: String) -> UUID? {
        guard text.hasPrefix(notePrefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(notePrefix.count)))
    }

    static func page(in text: String) -> (note: UUID, page: Int)? {
        guard text.hasPrefix(pagePrefix) else { return nil }
        let parts = text.dropFirst(pagePrefix.count).split(separator: ":")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let page = Int(parts[1]) else { return nil }
        return (id, page)
    }
}

/// Something dropped on a canvas, at a point in canvas coordinates.
enum CanvasDrop {
    case ink(PKDrawing)
    case image(UIImage)
    case text(String)
    case sticky(StickyNote)
    case note(UUID)
    case page(note: UUID, index: Int)
}

/// Takes drops on a note's canvas: ink, pictures, text, sticky notes,
/// notes (to open beside) and pages.
@MainActor
final class CanvasDropHandler: NSObject, UIDropInteractionDelegate {
    weak var host: NoteCanvasHostView?
    var onDrop: ((CanvasDrop, CGPoint) -> Void)?

    private static let accepted: [String] = [
        CanvasDragType.drawing, CanvasDragType.sticky, UTType.image.identifier, UTType.plainText.identifier, UTType.utf8PlainText.identifier,
    ]

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return onDrop != nil && session.hasItemsConforming(toTypeIdentifiers: Self.accepted)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let host else { return }
        let point = session.location(in: host.elementLayer)
        for item in session.items {
            load(item.itemProvider, at: point)
        }
    }

    private func load(_ provider: NSItemProvider, at point: CGPoint) {
        if provider.hasItemConformingToTypeIdentifier(CanvasDragType.drawing) {
            provider.loadDataRepresentation(forTypeIdentifier: CanvasDragType.drawing) { data, _ in
                guard let data, let drawing = try? PKDrawing(data: data) else { return }
                Task { @MainActor in self.onDrop?(.ink(drawing), point) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(CanvasDragType.sticky) {
            provider.loadDataRepresentation(forTypeIdentifier: CanvasDragType.sticky) { data, _ in
                guard let data, let note = try? JSONDecoder().decode(StickyNote.self, from: data) else { return }
                Task { @MainActor in self.onDrop?(.sticky(note), point) }
            }
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in self.onDrop?(.image(image), point) }
            }
        } else if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                Task { @MainActor in
                    if let id = CanvasDragType.noteID(in: text) {
                        self.onDrop?(.note(id), point)
                    } else if let page = CanvasDragType.page(in: text) {
                        self.onDrop?(.page(note: page.note, index: page.page), point)
                    } else {
                        self.onDrop?(.text(text), point)
                    }
                }
            }
        }
    }
}

/// Drags a lasso selection (ink, PDF text or an area) or a text box, picture
/// or sticky note out of the canvas: press and hold, then drag.
@MainActor
final class CanvasDragSource: NSObject, UIDragInteractionDelegate {
    weak var host: NoteCanvasHostView?

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let host else { return [] }
        // An element with the Text tool.
        if host.elementLayer.isInteractive {
            let point = session.location(in: host.elementLayer)
            guard let view = host.elementLayer.element(at: point), let provider = Self.provider(for: view) else { return [] }
            let item = UIDragItem(itemProvider: provider)
            item.localObject = view
            return [item]
        }
        // The lasso's selection.
        guard let payload = host.lasso.dragPayload(at: session.location(in: host.selectionOverlay)) else { return [] }
        let provider = NSItemProvider()
        if let drawing = payload.drawing {
            let data = drawing.dataRepresentation()
            provider.registerDataRepresentation(forTypeIdentifier: CanvasDragType.drawing, visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
        }
        if let text = payload.text {
            provider.registerObject(text as NSString, visibility: .all)
        }
        if let image = payload.image {
            provider.registerObject(image, visibility: .all)
        }
        let item = UIDragItem(itemProvider: provider)
        item.localObject = payload.image
        return [item]
    }

    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: UIDragSession) -> UITargetedDragPreview? {
        guard let host else { return nil }
        if let view = item.localObject as? UIView, view.superview != nil {
            return UITargetedDragPreview(view: view)
        }
        guard let image = item.localObject as? UIImage else { return nil }
        let view = UIImageView(image: image)
        let width: CGFloat = min(image.size.width, 260)
        view.frame = CGRect(x: 0, y: 0, width: width, height: width * image.size.height / max(image.size.width, 1))
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        let target = UIDragPreviewTarget(container: host, center: session.location(in: host))
        return UITargetedDragPreview(view: view, parameters: parameters, target: target)
    }

    private static func provider(for view: PageElementView) -> NSItemProvider? {
        if let box = view as? TextBoxView {
            return NSItemProvider(object: box.textView.attributedText.string as NSString)
        }
        if let picture = view as? ImageElementView, let image = picture.image {
            return NSItemProvider(object: image)
        }
        if let sticky = view as? StickyNoteView, let data = try? JSONEncoder().encode(sticky.note) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: CanvasDragType.sticky, visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
            if !sticky.note.text.isEmpty { provider.registerObject(sticky.note.text as NSString, visibility: .all) }
            return provider
        }
        return nil
    }
}
