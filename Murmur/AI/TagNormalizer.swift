import Foundation

/// Normalises AI tags (SPEC §5.3.5). Pure.
struct TagNormalizer: Sendable {
    var settings: TagSettings

    func normalize(_ tags: [String]) -> [String] {
        guard settings.maxCount > 0 else { return [] }
        let allowed: Set<String>? = settings.mode == .allowedOnly
            ? Set(settings.allowed.map(base).filter { !$0.isEmpty })
            : nil

        var result: [String] = []
        for tag in tags {
            let normalized = base(tag)
            guard !normalized.isEmpty, !normalized.allSatisfy(\.isNumber) else { continue }
            if let allowed, !allowed.contains(normalized) { continue }
            let prefixed = settings.prefix.isEmpty || normalized.hasPrefix(settings.prefix)
                ? normalized
                : settings.prefix + normalized
            if !result.contains(prefixed) { result.append(prefixed) }
            if result.count == settings.maxCount { break }
        }
        return result
    }

    /// Case, `#` and whitespace rules, without the prefix.
    private func base(_ tag: String) -> String {
        var text = tag.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.case == .lower { text = text.lowercased() }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: settings.separator)
    }
}
