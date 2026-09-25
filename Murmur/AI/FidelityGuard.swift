import Foundation

/// Rejects tidied text that strays from what was said (SPEC §6.4). Pure.
enum FidelityGuard {
    static let ratioRange = 0.80...1.10
    static let minimumKept = 0.85

    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mm", "like"]
    private static let fillerPhrases = [["you", "know"]]

    static func accepts(raw: String, tidied: String) -> Bool {
        let rawWords = contentWords(raw)
        let tidiedWords = contentWords(tidied)
        guard !rawWords.isEmpty else { return tidiedWords.isEmpty }

        let ratio = Double(tidiedWords.count) / Double(rawWords.count)
        guard ratioRange.contains(ratio) else { return false }

        let rawSet = Set(rawWords)
        let tidiedSet = Set(tidiedWords)
        let kept = Double(rawSet.intersection(tidiedSet).count) / Double(rawSet.count)
        return kept >= minimumKept
    }

    /// Lowercased words with fillers removed.
    static func contentWords(_ text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var index = 0
        while index < words.count {
            if let phrase = fillerPhrases.first(where: { Array(words[index...].prefix($0.count)) == $0 }) {
                index += phrase.count
                continue
            }
            if !fillers.contains(words[index]) { result.append(words[index]) }
            index += 1
        }
        return result
    }
}
