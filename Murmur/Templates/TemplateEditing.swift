import Foundation

/// Editor helpers for templates: highlighting, autocomplete and insertion (SPEC §5.3.6). Pure.
/// Positions are character offsets, so they work with both `String` and `AttributedString`.
enum TemplateEditing {
    struct Highlight: Equatable, Sendable {
        var range: Range<Int>
        var isKnown: Bool
    }

    /// A partly typed placeholder or filter name just before the cursor.
    struct CompletionQuery: Equatable, Sendable {
        var kind: PlaceholderCatalog.Entry.Kind
        var prefix: String
        /// The typed prefix, which a completion replaces.
        var range: Range<Int>
    }

    static func highlights(in text: String) -> [Highlight] {
        let known = Set(TemplateContext.knownPlaceholders)
        return TemplateParser.placeholderRanges(in: text).map { item in
            Highlight(
                range: text.distance(from: text.startIndex, to: item.range.lowerBound)
                    ..< text.distance(from: text.startIndex, to: item.range.upperBound),
                isKnown: known.contains(item.placeholder.name)
            )
        }
    }

    /// Unknown placeholders as written, in order, without duplicates.
    static func unknownPlaceholders(in text: String) -> [String] {
        let known = Set(TemplateContext.knownPlaceholders)
        var seen: [String] = []
        for case .placeholder(let placeholder) in TemplateParser.parse(text)
        where !known.contains(placeholder.name) && !seen.contains(placeholder.raw) {
            seen.append(placeholder.raw)
        }
        return seen
    }

    // MARK: Autocomplete

    /// What's being typed inside an unclosed `{{` on the cursor's line, if anything.
    static func completionQuery(text: String, cursor: Int) -> CompletionQuery? {
        guard cursor >= 0, cursor <= text.count else { return nil }
        let before = text.prefix(cursor)
        guard let open = before.range(of: "{{", options: .backwards) else { return nil }
        let inner = before[open.upperBound...]
        guard !inner.contains("}}"), !inner.contains(where: \.isNewline) else { return nil }

        let kind: PlaceholderCatalog.Entry.Kind
        let prefix: Substring
        if let bar = inner.lastIndex(of: "|") {
            kind = .filter
            prefix = inner[inner.index(after: bar)...]
        } else {
            kind = .placeholder
            prefix = inner
        }
        guard prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return CompletionQuery(kind: kind, prefix: String(prefix), range: (cursor - prefix.count)..<cursor)
    }

    static func completions(for query: CompletionQuery) -> [PlaceholderCatalog.Entry] {
        let entries = query.kind == .placeholder ? PlaceholderCatalog.placeholders : PlaceholderCatalog.filters
        let prefix = query.prefix.lowercased()
        return entries.filter { $0.name.hasPrefix(prefix) && $0.name != prefix }
    }

    /// Replaces the typed prefix with `entry`, adding `}}` if the placeholder isn't closed yet.
    static func complete(_ entry: PlaceholderCatalog.Entry, query: CompletionQuery, in text: String) -> (text: String, cursor: Int) {
        var inserted = entry.kind == .placeholder ? entry.name : String(entry.insertText.dropFirst())
        // Leave the cursor inside `default:""`'s quotes.
        var cursorBack = inserted.hasSuffix("\"\"") ? 1 : 0

        let after = text.dropFirst(query.range.upperBound)
        if !(after.hasPrefix("}}") || after.hasPrefix("|") || after.hasPrefix(":")) {
            inserted += "}}"
            if cursorBack > 0 { cursorBack += 2 }
        }
        let result = replace(query.range, in: text, with: inserted)
        return (result, query.range.lowerBound + inserted.count - cursorBack)
    }

    /// Inserts from the Insert menu. A filter goes before the `}}` of the placeholder the cursor
    /// is in or just after; a placeholder goes at the cursor.
    static func insert(_ entry: PlaceholderCatalog.Entry, into text: String, cursor: Int) -> (text: String, cursor: Int) {
        var position = min(max(cursor, 0), text.count)
        if entry.kind == .filter,
           let enclosing = highlights(in: text).first(where: { $0.range.lowerBound < position && position <= $0.range.upperBound }) {
            position = enclosing.range.upperBound - 2
        }
        let result = replace(position..<position, in: text, with: entry.insertText)
        let cursorBack = entry.insertText.hasSuffix("\"\"") ? 1 : 0
        return (result, position + entry.insertText.count - cursorBack)
    }

    private static func replace(_ range: Range<Int>, in text: String, with replacement: String) -> String {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return text.replacingCharacters(in: lower..<upper, with: replacement)
    }
}

extension TemplateContext {
    /// The note the editor previews against: the SPEC §5.4 example, recorded on Friday
    /// 25 September 2026 at 14:32. Without AI, the AI values are empty and the title falls back.
    static func sample(withAI: Bool, style: NoteStyleKind, appVersion: String = "", timeZone: TimeZone = .current) -> TemplateContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14, minute: 32, second: 5)) ?? .now
        let filename = withAI ? "2026-09-25-1432-chose-sqlite-over-json-for-the-cache" : "2026-09-25-1432-voice-note-14-32"

        var context = TemplateContext(
            title: withAI ? "Chose SQLite over JSON for the cache" : "Voice note 14:32",
            project: "Murmur",
            date: date,
            timeZone: timeZone,
            style: style,
            durationSeconds: 192,
            filename: filename,
            processing: withAI ? .tidied : .raw,
            appVersion: appVersion
        )
        if withAI {
            context.type = "decision"
            context.aiSummary = "Decided to move the local cache from JSON files to SQLite because loading was getting slow."
            context.aiKeyPoints = ["JSON cache took seconds to load", "SQLite handles partial reads", "Keep JSON export for debugging"]
            context.aiTags = ["sqlite", "cache", "performance"]
        }
        return context
    }
}
