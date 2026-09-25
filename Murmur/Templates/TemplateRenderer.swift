import Foundation

/// Renders templates against a `TemplateContext`. Pure: no I/O, no model.
/// Shared by front matter, filenames and (later) the timeline.
struct TemplateRenderer: Sendable {
    var context: TemplateContext

    /// A resolved placeholder after its filters ran.
    struct Resolved: Equatable {
        var value: TemplateValue
        var layout: ListLayout?
        /// Already formatted (e.g. by `|quote`), so emit without further YAML quoting.
        var verbatim = false
    }

    // MARK: Inline

    /// Substitutes placeholders as plain text: lists are joined with `, `, newlines become spaces.
    /// Unknown placeholders are left as they are.
    func renderInline(_ template: String) -> String {
        TemplateParser.parse(template).map { token -> String in
            switch token {
            case .literal(let text): return text
            case .placeholder(let placeholder):
                guard let resolved = resolve(placeholder) else { return placeholder.raw }
                return Self.singleLine(resolved.value.inlineText)
            }
        }.joined()
    }

    // MARK: Front matter

    /// Renders a front matter template line by line (SPEC §5.3.4 steps 1–3). Returns YAML text with no `---` fences.
    func renderFrontMatter(_ template: String, omitEmpty: Bool) -> String {
        let source = Self.stripFences(template)
        var output: [[String]] = source.map { renderLine($0, omitEmpty: omitEmpty) ?? [$0] }

        if omitEmpty {
            // Drop parent keys (`tags:`) whose child lines all rendered empty. Bottom-up handles nesting.
            for index in source.indices.reversed() {
                guard let indent = Self.bareKeyIndent(source[index]) else { continue }
                let children = Self.childIndices(of: index, indent: indent, in: source)
                if !children.isEmpty, children.allSatisfy({ output[$0].isEmpty }) {
                    output[index] = []
                }
            }
        }
        return output.flatMap { $0 }.joined(separator: "\n")
    }

    /// Returns the output lines for one template line, or nil to keep it unchanged.
    private func renderLine(_ line: String, omitEmpty: Bool) -> [String]? {
        let tokens = TemplateParser.parse(line)
        guard tokens.contains(where: { if case .placeholder = $0 { true } else { false } }) else { return nil }

        if let lines = renderListSplice(line, omitEmpty: omitEmpty) { return lines }
        if let lines = renderWholeValue(line, omitEmpty: omitEmpty) { return lines }
        return renderMixed(line, tokens: tokens, omitEmpty: omitEmpty)
    }

    /// `  - {{ai_tags}}` → one `- item` line per element at the same indent.
    private func renderListSplice(_ line: String, omitEmpty: Bool) -> [String]? {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = line.dropFirst(indent.count)
        guard rest.hasPrefix("- ") else { return nil }
        guard let placeholder = Self.soloPlaceholder(String(rest.dropFirst(2))) else { return nil }
        guard let resolved = resolve(placeholder) else { return [line] }

        let items: [String] = switch resolved.value {
        case .scalar(let value): [value]
        case .list(let values): values
        }
        return items.compactMap { item in
            if item.isEmpty { return omitEmpty ? nil : "\(indent)- \"\"" }
            return "\(indent)- \(resolved.verbatim ? item : YAMLScalar.format(item))"
        }
    }

    /// `key: {{placeholder}}` where the placeholder is the whole value.
    private func renderWholeValue(_ line: String, omitEmpty: Bool) -> [String]? {
        guard let (indent, key, value) = Self.splitKeyValue(line),
              let placeholder = Self.soloPlaceholder(value) else { return nil }
        guard let resolved = resolve(placeholder) else { return [line] }

        switch resolved.value {
        case .scalar(let text):
            if text.isEmpty { return omitEmpty ? [] : ["\(indent)\(key):"] }
            return ["\(indent)\(key): \(resolved.verbatim ? text : YAMLScalar.format(text))"]
        case .list(let values):
            let items = values.filter { !$0.isEmpty }
            if items.isEmpty { return omitEmpty ? [] : ["\(indent)\(key): []"] }
            let layout = resolved.layout ?? (context.style == .obsidian ? .block : .flow)
            switch layout {
            case .block:
                return ["\(indent)\(key):"] + items.map {
                    "\(indent)  - \(resolved.verbatim ? $0 : YAMLScalar.format($0))"
                }
            case .flow:
                let rendered = items.map { resolved.verbatim ? $0 : YAMLScalar.format($0, inFlow: true) }
                return ["\(indent)\(key): [\(rendered.joined(separator: ", "))]"]
            }
        }
    }

    /// Placeholders mixed with other text. Inside a double-quoted string, `"` and `\` are escaped.
    private func renderMixed(_ line: String, tokens: [TemplateToken], omitEmpty: Bool) -> [String] {
        var output = ""
        var inQuotes = false
        var allEmpty = true

        for token in tokens {
            switch token {
            case .literal(let text):
                var previous: Character?
                for character in text {
                    if character == "\"" && previous != "\\" { inQuotes.toggle() }
                    previous = character
                }
                output += text
            case .placeholder(let placeholder):
                guard let resolved = resolve(placeholder) else {
                    output += placeholder.raw
                    allEmpty = false
                    continue
                }
                let text = Self.singleLine(resolved.value.inlineText)
                if !text.isEmpty { allEmpty = false }
                output += inQuotes ? YAMLScalar.escapeInsideQuotes(text) : text
            }
        }

        if omitEmpty, allEmpty, let (_, _, value) = Self.splitKeyValue(output),
           ["", "\"\"", "''"].contains(value.trimmingCharacters(in: .whitespaces)) {
            return []
        }
        return [output]
    }

    // MARK: Placeholder resolution

    func resolve(_ placeholder: Placeholder) -> Resolved? {
        guard let value = context.value(for: placeholder.name, argument: placeholder.argument) else { return nil }
        var resolved = Resolved(value: value)
        for filter in placeholder.filters {
            apply(filter, to: &resolved)
        }
        return resolved
    }

    private func apply(_ filter: Placeholder.Filter, to resolved: inout Resolved) {
        func map(_ transform: (String) -> String) {
            switch resolved.value {
            case .scalar(let value): resolved.value = .scalar(value.isEmpty ? value : transform(value))
            case .list(let values): resolved.value = .list(values.map { $0.isEmpty ? $0 : transform($0) })
            }
        }

        switch filter.name {
        case "lower": map { $0.lowercased() }
        case "upper": map { $0.uppercased() }
        case "slug": map(Self.slug)
        case "wikilink": map { "[[\($0)]]" }
        case "quote":
            map { "\"\(YAMLScalar.escapeInsideQuotes($0))\"" }
            resolved.verbatim = true
        case "flow": resolved.layout = .flow
        case "block": resolved.layout = .block
        case "first":
            if case .list(let values) = resolved.value {
                resolved.value = .scalar(values.first(where: { !$0.isEmpty }) ?? "")
            }
        case "default":
            if resolved.value.isEmpty { resolved.value = .scalar(filter.argument ?? "") }
        default:
            break // Unknown filters are ignored.
        }
    }

    // MARK: Helpers

    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        var slug = ""
        var lastWasDash = false
        for scalar in folded.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// Removes leading and trailing `---` lines the user typed.
    static func stripFences(_ template: String) -> [String] {
        var lines = template.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func isFenceOrBlank(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed == "---"
        }
        while let first = lines.first, isFenceOrBlank(first) { lines.removeFirst() }
        while let last = lines.last, isFenceOrBlank(last) { lines.removeLast() }
        return lines
    }

    /// If `text` (trimmed) is exactly one placeholder, returns it.
    static func soloPlaceholder(_ text: String) -> Placeholder? {
        let tokens = TemplateParser.parse(text.trimmingCharacters(in: .whitespaces))
        guard tokens.count == 1, case .placeholder(let placeholder) = tokens[0] else { return nil }
        return placeholder
    }

    /// Splits `  key: value` into indent, key and value. Nil for list items, comments and non-key lines.
    static func splitKeyValue(_ line: String) -> (indent: String, key: String, value: String)? {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = line.dropFirst(indent.count)
        guard let first = rest.first, first != "#", first != "-" else { return nil }

        var key = ""
        var index = rest.startIndex
        if first == "\"" || first == "'" {
            guard let close = rest[rest.index(after: index)...].firstIndex(of: first) else { return nil }
            key = String(rest[index...close])
            index = rest.index(after: close)
            guard index < rest.endIndex, rest[index] == ":" else { return nil }
        } else {
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            key = String(rest[..<colon])
            if key.contains("{{") || key.hasSuffix(" ") { return nil }
            index = colon
        }
        let afterColon = rest.index(after: index)
        if afterColon < rest.endIndex, rest[afterColon] != " " && rest[afterColon] != "\t" { return nil }
        let value = String(rest[afterColon...]).trimmingCharacters(in: .whitespaces)
        return (indent, key, value)
    }

    /// Indent of a `key:` line with no inline value, or nil.
    private static func bareKeyIndent(_ line: String) -> Int? {
        guard let (indent, _, value) = splitKeyValue(line), value.isEmpty else { return nil }
        return indent.count
    }

    /// Lines belonging to the key at `index`: deeper-indented lines, or `- ` items at the same indent.
    private static func childIndices(of index: Int, indent: Int, in lines: [String]) -> [Int] {
        var children: [Int] = []
        var next = index + 1
        while next < lines.count {
            let line = lines[next]
            let lineIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, lineIndent > indent || (lineIndent == indent && trimmed.hasPrefix("- ")) else { break }
            children.append(next)
            next += 1
        }
        return children
    }
}
