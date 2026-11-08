import PDFKit
import SwiftUI

/// A cancel switch a background job can check.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Runs "Make Searchable" for notes in the background, so reading can go
/// on while the book is read page by page; one book at a time.
@MainActor
final class OCRCenter: ObservableObject {
    static let shared = OCRCenter()

    struct Job {
        let noteID: UUID
        var progress = BookOCR.Progress(done: 0, total: 0, read: 0)
        let flag = CancelFlag()
    }

    @Published private(set) var job: Job?
    /// The open note's session, to swap its PDF in place when the job ends.
    weak var session: EditorSession?

    func isRunning(for id: UUID) -> Bool { job?.noteID == id }

    func cancel() {
        job?.flag.cancel()
    }

    func start(noteID: UUID, store: LibraryStore, onlyScans: Bool = true) {
        guard job == nil else {
            CommandCenter.shared.say("Another book is being read; wait for it to finish")
            return
        }
        guard let content = try? store.loadContent(for: noteID), let source = content.pdf?.fileURL else { return }
        let target = content.directory.appendingPathComponent("document-\(UUID().uuidString.prefix(8)).pdf")
        let newJob = Job(noteID: noteID)
        job = newJob
        let flag = newJob.flag
        Task {
            do {
                let read = try await Task.detached(priority: .utility) { () throws -> Int in
                    guard let document = PDFDocument(url: source) else { throw PDFToolError.unreadable }
                    return try BookOCR.searchable(document, onlyScans: onlyScans, to: target, progress: { progress in
                        Task { @MainActor in OCRCenter.shared.job?.progress = progress }
                    }, isCancelled: { flag.isCancelled })
                }.value
                finish(noteID: noteID, file: target, read: read, store: store)
            } catch is CancellationError {
                job = nil
                CommandCenter.shared.say("Stopped making the book searchable")
            } catch {
                job = nil
                try? FileManager.default.removeItem(at: target)
                store.errorMessage = "The book couldn't be read: \(error.localizedDescription)"
            }
        }
    }

    private func finish(noteID: UUID, file: URL, read: Int, store: LibraryStore) {
        job = nil
        do {
            if let session, session.noteID == noteID {
                try session.replacePDF(with: file)
            } else {
                try store.replacePDF(of: noteID, with: file)
            }
            CommandCenter.shared.say(read == 0 ? "No scanned pages needed reading" : "\(read) pages can now be searched and selected")
        } catch {
            try? FileManager.default.removeItem(at: file)
            store.errorMessage = "The searchable copy couldn't be saved: \(error.localizedDescription)"
        }
    }
}
