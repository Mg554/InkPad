import SwiftUI
import UIKit

/// A file prepared for the system share sheet.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet (Save to Files, AirDrop, Mail, ...).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
