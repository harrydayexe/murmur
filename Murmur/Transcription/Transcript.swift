import Foundation

/// A finalized piece of transcript with its audio time range in seconds.
struct TranscriptSegment: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

enum TranscriptAssembler {
    static let paragraphGap = 2.0

    /// Joins segments, starting a new paragraph wherever the silence between them is 2.0 s or more.
    static func text(from segments: [TranscriptSegment]) -> String {
        var paragraphs: [String] = []
        var current = ""
        var previousEnd: Double?

        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let previousEnd, segment.start - previousEnd >= paragraphGap, !current.isEmpty {
                paragraphs.append(current)
                current = ""
            }
            current += current.isEmpty ? text : " " + text
            previousEnd = segment.end
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }
}

/// Combined global and project glossary (SPEC §4.5). Pure.
struct Glossary: Equatable, Sendable {
    struct Replacement: Equatable, Sendable {
        var from: String
        var to: String
    }

    /// Preferred spellings, given to the model.
    private(set) var preferred: [String] = []
    /// `from => to` rules, applied deterministically before the AI step.
    private(set) var replacements: [Replacement] = []

    init(entries: [String]) {
        for entry in entries {
            let parts = entry.components(separatedBy: "=>")
            if parts.count == 2 {
                let from = parts[0].trimmingCharacters(in: .whitespaces)
                let to = parts[1].trimmingCharacters(in: .whitespaces)
                guard !from.isEmpty else { continue }
                replacements.append(Replacement(from: from, to: to))
                if !to.isEmpty && !preferred.contains(to) { preferred.append(to) }
            } else {
                let term = entry.trimmingCharacters(in: .whitespaces)
                if !term.isEmpty && !preferred.contains(term) { preferred.append(term) }
            }
        }
    }

    /// Case-insensitive whole-word replacements.
    func apply(to text: String) -> String {
        var result = text
        for replacement in replacements {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: replacement.from) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement.to)
            )
        }
        return result
    }
}
