import Foundation

/// A `{{name:argument|filter|filter:"arg"}}` placeholder.
struct Placeholder: Equatable, Sendable {
    struct Filter: Equatable, Sendable {
        var name: String
        var argument: String?
    }

    var name: String
    /// Text after the first `:` in the name part, e.g. the format in `{{date:YYYY}}`.
    var argument: String?
    var filters: [Filter]
    /// The exact source text, including braces, so unknown placeholders can be left as they are.
    var raw: String
}

enum TemplateToken: Equatable, Sendable {
    case literal(String)
    case placeholder(Placeholder)
}

/// Splits template text into literals and placeholders. Pure.
enum TemplateParser {
    static func parse(_ text: String) -> [TemplateToken] {
        scan(text).map(\.token)
    }

    /// Every placeholder in `text` with where it sits, for highlighting in the editor.
    static func placeholderRanges(in text: String) -> [(range: Range<String.Index>, placeholder: Placeholder)] {
        scan(text).compactMap { item in
            guard case .placeholder(let placeholder) = item.token else { return nil }
            return (item.range, placeholder)
        }
    }

    private static func scan(_ text: String) -> [(token: TemplateToken, range: Range<String.Index>)] {
        var tokens: [(token: TemplateToken, range: Range<String.Index>)] = []
        var literal = ""
        var literalStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("{{"),
               let close = text.range(of: "}}", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                let inner = String(text[text.index(index, offsetBy: 2)..<close.lowerBound])
                let raw = String(text[index..<close.upperBound])
                if let placeholder = parsePlaceholder(inner, raw: raw) {
                    if !literal.isEmpty {
                        tokens.append((.literal(literal), literalStart..<index))
                        literal = ""
                    }
                    tokens.append((.placeholder(placeholder), index..<close.upperBound))
                    literalStart = close.upperBound
                } else {
                    literal += raw
                }
                index = close.upperBound
            } else {
                literal.append(text[index])
                index = text.index(after: index)
            }
        }
        if !literal.isEmpty { tokens.append((.literal(literal), literalStart..<text.endIndex)) }
        return tokens
    }

    /// Names of every placeholder in `text`.
    static func placeholderNames(in text: String) -> Set<String> {
        var names = Set<String>()
        for case .placeholder(let placeholder) in parse(text) {
            names.insert(placeholder.name)
        }
        return names
    }

    private static func parsePlaceholder(_ inner: String, raw: String) -> Placeholder? {
        let parts = splitOutsideQuotes(inner, separator: "|")
        guard let head = parts.first?.trimmingCharacters(in: .whitespaces), !head.isEmpty else { return nil }

        let name: String
        var argument: String?
        if let colon = head.firstIndex(of: ":") {
            name = String(head[..<colon]).trimmingCharacters(in: .whitespaces)
            argument = String(head[head.index(after: colon)...])
        } else {
            name = head
        }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }

        let filters = parts.dropFirst().map { part -> Placeholder.Filter in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { return .init(name: trimmed, argument: nil) }
            let filterName = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            var arg = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if arg.count >= 2, arg.hasPrefix("\""), arg.hasSuffix("\"") {
                arg = String(arg.dropFirst().dropLast())
            }
            return .init(name: filterName, argument: arg)
        }
        return Placeholder(name: name, argument: argument, filters: filters, raw: raw)
    }

    private static func splitOutsideQuotes(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if character == separator && !inQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }
}
