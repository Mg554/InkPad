import SwiftUI
import UIKit

/// Files prepared for the system share sheet.
struct ExportedFile: Identifiable {
    let id = UUID()
    let urls: [URL]

    init(url: URL) {
        urls = [url]
    }

    init(urls: [URL]) {
        self.urls = urls
    }
}

/// The system share sheet (Save to Files, AirDrop, Mail, ...).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
