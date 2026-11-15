import SwiftUI

/// An open comment thread: which pin, and what it holds now.
struct CommentRequest: Identifiable {
    let id: UUID
    var comment: NoteComment
    let page: Int
}

/// A comment pin in a note, with the page it is on.
struct CommentItem: Identifiable {
    let id: UUID
    let comment: NoteComment
    let page: Int
}

/// What the owner chose to do with a comment thread.
enum CommentOutcome {
    case save(NoteComment)
    case delete
}

/// Edits a comment thread: the comment's text, replies, resolve and delete.
/// Saving an empty thread (no text and no replies) removes the pin.
struct CommentThreadEditor: View {
    @Environment(\.dismiss) private var dismiss
    let request: CommentRequest
    let finish: (CommentOutcome) -> Void

    @State private var comment = NoteComment()
    @State private var reply = ""

    private var isResolved: Bool { comment.isResolved ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Write a comment…"), text: $comment.text, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text(tr("Comment"))
                } footer: {
                    Text(trMessage("On page \(request.page + 1)."))
                }
                if !(comment.replies ?? []).isEmpty {
                    Section(tr("Replies")) {
                        ForEach(comment.replies ?? []) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text)
                                Text(item.createdAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { comment.replies?.remove(atOffsets: $0) }
                    }
                }
                Section {
                    HStack {
                        TextField(tr("Add a reply…"), text: $reply)
                        Button {
                            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            comment.replies = (comment.replies ?? []) + [NoteComment(text: text)]
                            reply = ""
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title3)
                        }
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(tr("Comment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        finish(.delete)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text(tr("Delete")))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        comment.isResolved = isResolved ? nil : true
                    } label: {
                        Image(systemName: isResolved ? "checkmark.seal.fill" : "checkmark.seal")
                            .foregroundStyle(isResolved ? Color.secondary : Color.yellow)
                    }
                    .accessibilityLabel(Text(tr(isResolved ? "Mark Unresolved" : "Mark Resolved")))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done")) {
                        let empty = comment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && (comment.replies ?? []).isEmpty
                        finish(empty ? .delete : .save(comment))
                        dismiss()
                    }
                }
            }
            .onAppear { comment = request.comment }
        }
    }
}

/// Every comment pin in the note, oldest first.
struct CommentListView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [CommentItem]
    let open: (UUID, Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        tr("No Comments"),
                        systemImage: "bubble.left.and.bubble.right.fill",
                        description: Text(tr("Add one from the + menu or the lasso."))
                    )
                }
                ForEach(items) { item in
                    Button {
                        open(item.id, item.page)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.comment.isResolved ?? false ? "checkmark.seal.fill" : "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(item.comment.isResolved ?? false ? Color.secondary : Color.yellow)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.comment.text.isEmpty ? trMessage("On page \(item.page + 1).") : item.comment.text)
                                    .lineLimit(2)
                                Text(trMessage("Page \(item.page + 1)."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(tr("Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}
