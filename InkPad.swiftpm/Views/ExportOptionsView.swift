import SwiftUI

/// Notability-style "Export as..." options.
struct ExportOptionsView: View {
    enum RangeChoice: String, CaseIterable, Identifiable {
        case all = "All Pages"
        case current = "Current Page"
        case custom = "Custom"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    let pageCount: Int
    let currentPage: Int
    let onExport: (PDFExportOptions) -> Void

    @State private var options = PDFExportOptions()
    @State private var range: RangeChoice = .all
    @State private var firstPage = 1
    @State private var lastPage = 1
    @State private var usesPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section("File Format") {
                    Label("PDF", systemImage: "doc.richtext")
                }

                Section("More Options") {
                    Toggle(isOn: $options.includePaper) {
                        Label("Include Background Paper", systemImage: "squareshape.split.3x3")
                    }
                    Toggle(isOn: $options.addMargins) {
                        Label("Add Page Margins", systemImage: "rectangle.inset.filled")
                    }
                    Picker(selection: $range) {
                        ForEach(RangeChoice.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label("Page Range", systemImage: "book.pages")
                    }
                    if range == .custom {
                        Stepper("From page \(firstPage)", value: $firstPage, in: 1...max(lastPage, 1))
                        Stepper("To page \(lastPage)", value: $lastPage, in: firstPage...max(pageCount, 1))
                    }
                    Toggle(isOn: $usesPassword) {
                        Label("Password", systemImage: "lock")
                    }
                    if usesPassword {
                        SecureField("Password to open the PDF", text: $options.password)
                    }
                }
            }
            .navigationTitle("Export as…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        onExport(resolvedOptions)
                        dismiss()
                    }
                    .disabled(usesPassword && options.password.isEmpty)
                }
            }
            .onAppear {
                lastPage = max(pageCount, 1)
            }
        }
    }

    private var resolvedOptions: PDFExportOptions {
        var resolved = options
        if !usesPassword { resolved.password = "" }
        switch range {
        case .all: resolved.pageRange = nil
        case .current: resolved.pageRange = currentPage...currentPage
        case .custom: resolved.pageRange = (firstPage - 1)...(max(lastPage, firstPage) - 1)
        }
        return resolved
    }
}
