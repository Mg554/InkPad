import Foundation

/// Something to create, read from a typed or spoken sentence such as
/// "remind me to call Sara tomorrow at 9", "ذكرني بالمحاضرة غداً الساعة 9"
/// or "coffee 15". Read on the iPad, in English and Arabic.
enum CommandIntent: Equatable {
    case reminder(title: String, due: Date?, hasTime: Bool)
    case task(title: String, due: Date?)
    case expense(title: String, amount: Decimal, category: Expense.Category, isIncome: Bool)
    case note(title: String)
    case textNote(title: String)
    case mindMap(title: String)
}

enum CommandParser {
    /// What the text most likely asks for, best guess first.
    static func parse(_ raw: String, now: Date = Date()) -> [CommandIntent] {
        let text = westernDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        let key = normalized(text)
        let when = findDate(in: text, now: now)
        var results: [CommandIntent] = []

        if let trigger = match(key, reminderWords) {
            results.append(.reminder(title: title(from: text, removing: [trigger] + (when?.parts ?? [])), due: when?.date, hasTime: when?.hasTime ?? false))
        }
        if let trigger = match(key, taskWords) {
            results.append(.task(title: title(from: text, removing: [trigger] + (when?.parts ?? [])), due: when?.date))
        }
        if let trigger = match(key, mindMapWords) {
            results.append(.mindMap(title: title(from: text, removing: [trigger])))
        } else if let trigger = match(key, textNoteWords) {
            results.append(.textNote(title: title(from: text, removing: [trigger])))
        } else if let trigger = match(key, noteWords) {
            results.append(.note(title: title(from: text, removing: [trigger])))
        }

        // Money: an amount with a spending word, or "something 15".
        if let amount = amount(in: text, ignoring: when?.parts ?? []) {
            let income = match(key, incomeWords)
            let spent = match(key, expenseWords)
            let label = title(from: text, removing: [income, spent, amount.matched].compactMap { $0 } + currencyWords)
            let category = income != nil ? Expense.Category.salary : guessCategory(key)
            let intent = CommandIntent.expense(title: label, amount: amount.value, category: category, isIncome: income != nil)
            if income != nil || spent != nil {
                results.insert(intent, at: 0)
            } else if results.isEmpty, text.split(separator: " ").count <= 5 {
                results.append(intent)
            }
        }

        // A date with no other clue reads as a reminder.
        if results.isEmpty, let when, when.matched.count < text.count {
            results.append(.reminder(title: title(from: text, removing: when.parts), due: when.date, hasTime: when.hasTime))
        }
        return results
    }

    // MARK: Words

    private static let reminderWords = ["remind me to", "remind me about", "remind me", "reminder", "remind", "ذكرني ب", "ذكرني", "تذكير ب", "تذكير", "نبهني", "فكرني"]
    private static let taskWords = ["add task", "new task", "task", "todo", "to do", "to-do", "مهمه جديده", "مهمه", "اضف مهمه"]
    private static let noteWords = ["new note", "create note", "note", "ملاحظه جديده", "ملاحظه"]
    private static let textNoteWords = ["text note", "markdown note", "ملاحظه نصيه"]
    private static let mindMapWords = ["mind map", "mindmap", "new map", "خريطه ذهنيه", "خريطه"]
    private static let expenseWords = ["spent", "paid", "pay", "expense", "bought", "cost", "صرفت", "دفعت", "مصروف", "اشتريت", "سعر"]
    private static let incomeWords = ["earned", "income", "salary", "received", "got paid", "راتب", "دخل", "استلمت", "قبضت"]
    private static let currencyWords = ["dollars", "dollar", "usd", "$", "€", "euro", "shekel", "shekels", "nis", "₪", "شيكل", "دولار", "دينار", "ريال", "جنيه", "ليرة", "درهم"]

    private static let categories: [(Expense.Category, [String])] = [
        (.food, ["coffee", "lunch", "dinner", "breakfast", "food", "restaurant", "pizza", "burger", "snack", "groceries", "قهوه", "غداء", "عشاء", "فطور", "اكل", "مطعم", "بيتزا", "شاورما", "خضار", "سوبرماركت"]),
        (.transport, ["taxi", "uber", "bus", "gas", "fuel", "train", "parking", "تاكسي", "باص", "بنزين", "مواصلات", "اوبر", "موقف"]),
        (.shopping, ["shop", "clothes", "shoes", "amazon", "تسوق", "ملابس", "حذاء", "مول"]),
        (.bills, ["bill", "rent", "electricity", "water", "internet", "phone", "فاتوره", "ايجار", "كهرباء", "ماء", "انترنت", "جوال"]),
        (.health, ["doctor", "pharmacy", "medicine", "hospital", "dentist", "gym", "صيدليه", "دواء", "طبيب", "دكتور", "مستشفى", "نادي"]),
        (.education, ["book", "course", "tuition", "class", "exam", "كتاب", "دوره", "جامعه", "قسط", "امتحان"]),
        (.entertainment, ["movie", "game", "netflix", "cinema", "concert", "سينما", "لعبه", "فيلم", "نتفلكس"]),
    ]

    private static func guessCategory(_ key: String) -> Expense.Category {
        categories.first { _, words in words.contains { key.contains($0) } }?.0 ?? .other
    }

    /// The first trigger found, preferring the longest.
    private static func match(_ key: String, _ words: [String]) -> String? {
        words.sorted { $0.count > $1.count }.first { word in
            let normalizedWord = normalized(word)
            guard let range = key.range(of: normalizedWord) else { return false }
            // Whole words only (Arabic prefixes like ب are allowed after).
            let before = range.lowerBound == key.startIndex || key[key.index(before: range.lowerBound)] == " "
            return before
        }
    }

    // MARK: Text helpers

    /// Lowercased, Arabic letters unified, marks removed, for matching.
    static func normalized(_ text: String) -> String {
        var result = text.lowercased()
        let marks = CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0640}")
        result = String(result.unicodeScalars.filter { !marks.contains($0) }.map(Character.init))
        for (from, to) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ؤ", "و"), ("ئ", "ي")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    static func westernDigits(_ text: String) -> String {
        let arabic = Array("٠١٢٣٤٥٦٧٨٩")
        let persian = Array("۰۱۲۳۴۵۶۷۸۹")
        return String(text.map { character in
            if let index = arabic.firstIndex(of: character) ?? persian.firstIndex(of: character) {
                return Character(String(index))
            }
            return character == "٫" ? "." : character
        })
    }

    /// The text without the command words and date, as a title.
    private static func title(from text: String, removing parts: [String]) -> String {
        var result = " " + text + " "
        for part in parts.sorted(by: { $0.count > $1.count }) where !part.isEmpty {
            // Match ignoring Arabic letter forms and case.
            if let range = rangeIgnoringForms(of: part, in: result) {
                result.replaceSubrange(range, with: " ")
            }
        }
        let fillers = ["to", "about", "that", "for", "at", "on", "a", "an", "ان", "عن", "على", "في", "ب", "يوم"].map(normalized)
        var words = result.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, fillers.contains(normalized(first)) { words.removeFirst() }
        while let last = words.last, fillers.contains(normalized(last)) { words.removeLast() }
        // "بالمحاضرة" -> "المحاضرة" after "ذكرني".
        if let first = words.first, first.hasPrefix("بال") { words[0] = String(first.dropFirst()) }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.،:;-"))
    }

    private static func rangeIgnoringForms(of part: String, in text: String) -> Range<String.Index>? {
        if let exact = text.range(of: part, options: [.caseInsensitive, .diacriticInsensitive]) { return exact }
        // Walk the text comparing normalized forms of same-length slices.
        let target = normalized(part)
        let characters = Array(text)
        let length = part.count
        guard length <= characters.count else { return nil }
        for start in 0...(characters.count - length) {
            if normalized(String(characters[start..<start + length])) == target {
                let lower = text.index(text.startIndex, offsetBy: start)
                return lower..<text.index(lower, offsetBy: length)
            }
        }
        return nil
    }

    // MARK: Amounts

    private static func amount(in text: String, ignoring dateParts: [String]) -> (value: Decimal, matched: String)? {
        var searchable = text
        for part in dateParts {
            if let range = searchable.range(of: part) { searchable.replaceSubrange(range, with: " ") }
        }
        guard let regex = try? NSRegularExpression(pattern: #"[$€₪£]?\s?(\d+(?:[.,]\d{1,2})?)\s?(?:[$€₪£]|k\b)?"#) else { return nil }
        let range = NSRange(searchable.startIndex..., in: searchable)
        guard let match = regex.firstMatch(in: searchable, range: range),
              let whole = Range(match.range, in: searchable),
              let digits = Range(match.range(at: 1), in: searchable),
              let value = Decimal(string: searchable[digits].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        let matched = String(searchable[whole]).trimmingCharacters(in: .whitespaces)
        let multiplier: Decimal = matched.lowercased().hasSuffix("k") ? 1000 : 1
        return (value * multiplier, matched)
    }

    // MARK: Dates

    struct FoundDate {
        let date: Date
        let hasTime: Bool
        /// The words that said it, to take out of the title.
        let parts: [String]
        var matched: String { parts.joined(separator: " ") }
    }

    static func findDate(in text: String, now: Date = Date()) -> FoundDate? {
        arabicDate(in: text, now: now) ?? detectedDate(in: text, now: now)
    }

    /// English (and other) dates through Apple's data detector.
    private static func detectedDate(in text: String, now: Date) -> FoundDate? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date,
              let range = Range(match.range, in: text)
        else { return nil }
        let matched = String(text[range])
        let lower = matched.lowercased()
        let hasTime = lower.range(of: #"\d\s*(:|am|pm|a\.m|p\.m|o'clock)|noon|midnight|morning|evening|night|at \d"#, options: .regularExpression) != nil
        return FoundDate(date: date, hasTime: hasTime, parts: [matched])
    }

    /// اليوم، غداً، بكرة، بعد غد، أيام الأسبوع، الساعة ٩ صباحاً/مساءً.
    private static func arabicDate(in text: String, now: Date) -> FoundDate? {
        let calendar = Calendar.current
        let key = normalized(text)
        var day: Date?
        var pieces: [String] = []
        let dayWords: [(String, Int)] = [("بعد بكره", 2), ("بعد بكرا", 2), ("بعد غد", 2), ("بكره", 1), ("بكرا", 1), ("غدا", 1), ("بكرة", 1), ("اليوم", 0)]
        for (word, offset) in dayWords where key.contains(normalized(word)) {
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
            pieces.append(word)
            break
        }
        if day == nil {
            let weekdays = ["الاحد": 1, "الاثنين": 2, "الثلاثاء": 3, "الاربعاء": 4, "الخميس": 5, "الجمعه": 6, "السبت": 7]
            for (word, weekday) in weekdays where key.contains(word) {
                day = calendar.nextDate(after: now, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
                pieces.append(word)
                break
            }
        }
        // A time: "الساعة 9", "9 الصبح", "9:30 مساء".
        var hour: Int?
        var minute = 0
        if let regex = try? NSRegularExpression(pattern: #"(?:الساعه|الساعة|ساعه|ساعة)?\s*(\d{1,2})(?::(\d{2}))?\s*(صباحا|صباحاً|الصبح|الصباح|ص|مساء|مساءً|المسا|المساء|بالليل|الليل|الظهر|العصر|م)?"#),
           day != nil || key.contains("الساعه") {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let whole = Range(match.range, in: text), let hourRange = Range(match.range(at: 1), in: text) else { continue }
                let wholeText = String(text[whole])
                // A bare number counts only with "الساعة" or a part of day.
                let hasClue = wholeText.contains("ساع") || match.range(at: 3).location != NSNotFound
                guard hasClue || day != nil, var value = Int(text[hourRange]), value <= 23 else { continue }
                if let minuteRange = Range(match.range(at: 2), in: text) { minute = Int(text[minuteRange]) ?? 0 }
                if let partRange = Range(match.range(at: 3), in: text) {
                    let part = normalized(String(text[partRange]))
                    let isEvening = ["مساء", "المسا", "المساء", "بالليل", "الليل", "العصر", "م"].contains(part)
                    if isEvening && value < 12 { value += 12 }
                    if part == "الظهر" && value < 6 { value += 12 }
                } else if value >= 1 && value <= 6 {
                    value += 12 // "الساعة 3" means the afternoon.
                }
                hour = value
                pieces.append(wholeText.trimmingCharacters(in: .whitespaces))
                break
            }
        }
        guard day != nil || hour != nil else { return nil }
        var date = day ?? calendar.startOfDay(for: now)
        if let hour {
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            // A time already past today means tomorrow.
            if day == nil, date < now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        }
        return FoundDate(date: date, hasTime: hour != nil, parts: pieces)
    }
}
