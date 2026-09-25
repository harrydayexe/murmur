import Foundation

/// YAML scalar formatting with minimal quoting. Pure.
enum YAMLScalar {
    private static let reservedWords: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "~", "y", "n"]
    private static let indicatorStarts: Set<Character> = [",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`"]

    /// `value` as a plain scalar if that's safe, otherwise double-quoted.
    static func format(_ value: String, inFlow: Bool = false) -> String {
        needsQuoting(value, inFlow: inFlow) ? doubleQuoted(value) : value
    }

    static func needsQuoting(_ value: String, inFlow: Bool = false) -> Bool {
        guard let first = value.first, let last = value.last else { return true }
        if first.isWhitespace || last.isWhitespace { return true }
        if value.contains(where: { $0.isNewline || $0 == "\t" }) { return true }
        if indicatorStarts.contains(first) { return true }
        if ["-", "?", ":"].contains(first), value.count == 1 || value.dropFirst().first == " " { return true }
        if value.contains(": ") || value.contains(" #") || last == ":" { return true }
        if reservedWords.contains(value.lowercased()) { return true }
        if inFlow, value.contains(where: { ",[]{}".contains($0) }) { return true }
        return false
    }

    static func doubleQuoted(_ value: String) -> String {
        var escaped = escapeInsideQuotes(value)
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// Escapes `\` and `"` for insertion inside an existing double-quoted string.
    static func escapeInsideQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// True if the plain scalar would be read as a number.
    static func looksLikeNumber(_ value: String) -> Bool {
        Double(value) != nil || Int(value) != nil
    }
}

enum ListLayout: Sendable {
    case flow
    case block
}

/// An ordered YAML tree, used for the structural merge in `append` mode.
indirect enum YAMLValue: Equatable, Sendable {
    /// `quoted` records whether the source quoted it, so `"123"` stays a string.
    case scalar(String, quoted: Bool)
    case sequence([YAMLValue])
    case mapping([(key: String, value: YAMLValue)])

    static func == (lhs: YAMLValue, rhs: YAMLValue) -> Bool {
        switch (lhs, rhs) {
        case let (.scalar(a, qa), .scalar(b, qb)): a == b && qa == qb
        case let (.sequence(a), .sequence(b)): a == b
        case let (.mapping(a), .mapping(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }
}

/// Emits a `YAMLValue` mapping as front matter text (no `---` fences).
/// Block lists in obsidian style, flow lists in standard style, minimal quoting, wikilinks always quoted.
enum YAMLEmitter {
    static func emit(_ root: [(key: String, value: YAMLValue)], listLayout: ListLayout) -> String {
        var lines: [String] = []
        emitMapping(root, indent: 0, layout: listLayout, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func emitMapping(_ pairs: [(key: String, value: YAMLValue)], indent: Int, layout: ListLayout, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for (key, value) in pairs {
            let keyText = YAMLScalar.format(key)
            switch value {
            case .scalar(let text, let quoted):
                lines.append("\(pad)\(keyText): \(scalar(text, quoted: quoted, inFlow: false))")
            case .sequence(let items):
                let allScalars = items.allSatisfy { if case .scalar = $0 { true } else { false } }
                if items.isEmpty {
                    lines.append("\(pad)\(keyText): []")
                } else if layout == .flow && allScalars {
                    let rendered = items.map { item -> String in
                        guard case .scalar(let text, let quoted) = item else { return "" }
                        return scalar(text, quoted: quoted, inFlow: true)
                    }
                    lines.append("\(pad)\(keyText): [\(rendered.joined(separator: ", "))]")
                } else {
                    lines.append("\(pad)\(keyText):")
                    emitSequence(items, indent: indent + 2, layout: layout, into: &lines)
                }
            case .mapping(let nested):
                lines.append("\(pad)\(keyText):")
                emitMapping(nested, indent: indent + 2, layout: layout, into: &lines)
            }
        }
    }

    private static func emitSequence(_ items: [YAMLValue], indent: Int, layout: ListLayout, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for item in items {
            switch item {
            case .scalar(let text, let quoted):
                lines.append("\(pad)- \(scalar(text, quoted: quoted, inFlow: false))")
            case .sequence(let nested):
                lines.append("\(pad)-")
                emitSequence(nested, indent: indent + 2, layout: layout, into: &lines)
            case .mapping(let nested):
                var nestedLines: [String] = []
                emitMapping(nested, indent: indent + 2, layout: layout, into: &nestedLines)
                if let first = nestedLines.first {
                    lines.append("\(pad)- " + first.dropFirst(indent + 2))
                    lines.append(contentsOf: nestedLines.dropFirst())
                }
            }
        }
    }

    private static func scalar(_ text: String, quoted: Bool, inFlow: Bool) -> String {
        if !quoted {
            // Plain in the source, so it's already valid plain YAML (and keeps its type, e.g. `true`).
            if inFlow, text.contains(where: { ",[]{}".contains($0) }) { return YAMLScalar.doubleQuoted(text) }
            return text
        }
        if YAMLScalar.needsQuoting(text, inFlow: inFlow) || YAMLScalar.looksLikeNumber(text) {
            return YAMLScalar.doubleQuoted(text)
        }
        return text
    }
}
