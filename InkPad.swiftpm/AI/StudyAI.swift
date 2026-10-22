import Foundation

/// What InkPad asks the AI to do with notes, and how it reads the answers.
enum StudyAI {
    static let chatInstructions = """
        You are InkPad's study assistant. The user's notes are below, each starting with "=== Note: <title> ===". \
        Answer from the notes and name the note you used in square brackets, like [Biology Lecture 3]. \
        If the notes don't cover the question, say so, then answer from general knowledge and say that you did. \
        Explain clearly, like a good tutor. Use Markdown. Reply in the language the user writes in.
        """

    static func chatSystem(notes: String) -> String {
        chatInstructions + "\n\n" + (notes.isEmpty ? "(No notes were found.)" : notes)
    }

    // MARK: Flashcards

    static func flashcardsPrompt(notes: String, count: Int) -> String {
        """
        Make \(count) flashcards for studying the notes below. Each card asks one clear question or names one term \
        on the front, and gives a short, complete answer on the back. Cover the most important ideas. \
        Write in the same language as the notes.
        Answer with JSON only, in exactly this shape:
        {"cards": [{"front": "...", "back": "..."}]}

        Notes:
        \(notes)
        """
    }

    static func flashcards(from reply: String) throws -> [Flashcard] {
        guard let json = AIJSON.object(in: reply), let cards = json["cards"] as? [[String: Any]] else {
            throw AIError.unreadable
        }
        let result = cards.compactMap { card -> Flashcard? in
            guard let front = (card["front"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let back = (card["back"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !front.isEmpty, !back.isEmpty
            else { return nil }
            return Flashcard(front: front, back: back)
        }
        guard !result.isEmpty else { throw AIError.empty }
        return result
    }

    // MARK: Quizzes

    static func quizPrompt(notes: String, count: Int) -> String {
        """
        Write a multiple-choice quiz of \(count) questions on the notes below. Each question has 4 choices with \
        exactly one right answer, and a one or two sentence explanation of why it is right. \
        Mix easy and harder questions. Write in the same language as the notes.
        Answer with JSON only, in exactly this shape (answer is the index of the right choice, from 0):
        {"questions": [{"question": "...", "choices": ["...", "...", "...", "..."], "answer": 0, "explanation": "..."}]}

        Notes:
        \(notes)
        """
    }

    static func quizQuestions(from reply: String) throws -> [QuizQuestion] {
        guard let json = AIJSON.object(in: reply), let questions = json["questions"] as? [[String: Any]] else {
            throw AIError.unreadable
        }
        let result = questions.compactMap { item -> QuizQuestion? in
            guard let question = item["question"] as? String,
                  let choices = item["choices"] as? [String], choices.count >= 2
            else { return nil }
            let answer = (item["answer"] as? Int) ?? Int(item["answer"] as? String ?? "") ?? 0
            return QuizQuestion(
                id: UUID(),
                question: question,
                choices: choices,
                answer: min(max(answer, 0), choices.count - 1),
                explanation: item["explanation"] as? String ?? ""
            )
        }
        guard !result.isEmpty else { throw AIError.empty }
        return result
    }

    // MARK: Smart notes

    static func summaryPrompt(notes: String) -> String {
        """
        Turn the notes below into clear, well organized study notes in Markdown: a "# " title, short sections \
        with "## " headings, bullet points for the key facts, **bold** for key terms, and a "## Summary" \
        section at the end. Keep every important fact; leave out repetition. Write in the same language as the notes.

        Notes:
        \(notes)
        """
    }

    // MARK: Slides

    static func slidesPrompt(notes: String, format: DeckFormat, length: DeckLength, focus: String) -> String {
        let style = format == .detailed
            ? "Each slide has 3 to 5 bullets written as complete, informative sentences."
            : "Each slide has at most 3 short bullets (under 10 words). Put what the presenter says in notes."
        let trimmedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusLine = trimmedFocus.isEmpty ? "" : "The audience and focus: \(trimmedFocus).\n"
        return """
            Make a presentation from the notes below, like NotebookLM's slide decks: a clear story from \
            introduction to conclusion, \(length.contentSlides) content slides. \(style)
            \(focusLine)Use only facts from the notes. Write in the same language as the notes.
            For each slide choose an icon from: idea, data, time, people, goal, process, problem, question, money, \
            science, health, technology, book, world, law, math, summary. Use layout "quote" only for a striking \
            quotation from the notes (put the quote in title).
            Answer with JSON only, in exactly this shape:
            {"title": "...", "subtitle": "...", "slides": [{"title": "...", "layout": "bullets", "bullets": ["..."], \
            "notes": "...", "icon": "idea"}], "takeaways": ["...", "...", "..."]}

            Notes:
            \(notes)
            """
    }

    static func outline(fromSlidesReply reply: String, format: DeckFormat) throws -> DeckOutline {
        guard let json = AIJSON.object(in: reply), let items = json["slides"] as? [[String: Any]] else {
            throw AIError.unreadable
        }
        let slides = items.compactMap { item -> Slide? in
            let title = (item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bullets = (item["bullets"] as? [String] ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !title.isEmpty || !bullets.isEmpty else { return nil }
            let layout: Slide.Layout = (item["layout"] as? String) == "quote" ? .quote : .bullets
            let icon = item["icon"] as? String ?? ""
            return Slide(
                layout: layout,
                title: title,
                bullets: Array(bullets.prefix(format.bulletsPerSlide + 1)),
                speakerNotes: item["notes"] as? String ?? "",
                symbol: icon.isEmpty
                    ? SlideSymbols.symbol(for: ([title] + bullets).joined(separator: " "))
                    : SlideSymbols.symbol(forKeyword: icon)
            )
        }
        guard !slides.isEmpty else { throw AIError.empty }
        return DeckOutline(
            title: json["title"] as? String ?? "",
            subtitle: json["subtitle"] as? String ?? "",
            slides: slides,
            takeaways: Array((json["takeaways"] as? [String] ?? []).prefix(5))
        )
    }
}
