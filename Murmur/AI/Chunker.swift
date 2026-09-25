import Foundation

/// Splits text into chunks that fit a token budget: by paragraph, then sentence, then word.
/// Pure apart from the injected token counter.
enum Chunker {
    static func chunks(
        of text: String,
        budget: Int,
        tokenCount: (String) async throws -> Int
    ) async rethrows -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Break anything too big into pieces that each fit.
        var pieces: [(text: String, endsParagraph: Bool)] = []
        for paragraph in paragraphs {
            if try await tokenCount(paragraph) <= budget {
                pieces.append((paragraph, true))
                continue
            }
            let parts = try await split(paragraph, budget: budget, tokenCount: tokenCount)
            for (index, part) in parts.enumerated() {
                pieces.append((part, index == parts.count - 1))
            }
        }

        // Greedily pack pieces into chunks.
        var chunks: [String] = []
        var current = ""
        var previousEndedParagraph = true
        for piece in pieces {
            let separator = previousEndedParagraph ? "\n\n" : " "
            let candidate = current.isEmpty ? piece.text : current + separator + piece.text
            let fits = try await tokenCount(candidate) <= budget
            if current.isEmpty || fits {
                current = candidate
            } else {
                chunks.append(current)
                current = piece.text
            }
            previousEndedParagraph = piece.endsParagraph
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Splits an oversized paragraph into sentence groups, falling back to words for very long sentences.
    private static func split(
        _ paragraph: String,
        budget: Int,
        tokenCount: (String) async throws -> Int
    ) async rethrows -> [String] {
        var units: [String] = []
        for sentence in sentences(in: paragraph) {
            if try await tokenCount(sentence) <= budget {
                units.append(sentence)
            } else {
                units.append(contentsOf: try await pack(sentence.split(separator: " ").map(String.init), budget: budget, tokenCount: tokenCount))
            }
        }
        return try await pack(units, budget: budget, tokenCount: tokenCount)
    }

    private static func pack(
        _ units: [String],
        budget: Int,
        tokenCount: (String) async throws -> Int
    ) async rethrows -> [String] {
        var result: [String] = []
        var current = ""
        for unit in units {
            let candidate = current.isEmpty ? unit : current + " " + unit
            let fits = try await tokenCount(candidate) <= budget
            if current.isEmpty || fits {
                current = candidate
            } else {
                result.append(current)
                current = unit
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func sentences(in text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }
}
