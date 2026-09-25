import Foundation
import FoundationModels

/// Tidies a transcript with the on-device model, one new session per chunk (SPEC §6.4).
struct Polisher: TextPolishing {
    static func instructions(glossary: [String]) -> String {
        let terms = glossary.isEmpty ? "(none)" : glossary.joined(separator: ", ")
        return """
        You are a careful transcript editor. You receive a section of a spoken voice note.
        Return the same text with ONLY these changes:
        - fix punctuation, capitalisation and obvious speech-recognition errors
        - remove filler words (um, uh, er, "you know", "like" used as filler) and immediate repetitions or false starts
        - split into paragraphs where the topic shifts
        - use these spellings for project terms: \(terms)
        Do NOT summarise, paraphrase, reorder, add headings, add commentary, or change the speaker's first-person voice.
        Output only the edited text.
        """
    }

    func polish(
        _ text: String,
        glossary: [String],
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> PolishResult {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        try ModelStatus.requireAvailable(model)

        let instructions = Self.instructions(glossary: glossary)
        let instructionTokens = try await model.tokenCount(for: Instructions(instructions))
        let budget = max(64, min(1200, (model.contextSize - instructionTokens - 200) / 2))
        let chunks = try await Chunker.chunks(of: text, budget: budget) { try await model.tokenCount(for: $0) }

        var output: [String] = []
        var fellBack = false
        for (index, chunk) in chunks.enumerated() {
            await progress(index + 1, chunks.count)
            let result = await tidy(chunk, model: model, instructions: instructions, mayRetry: true)
            output.append(result.text)
            fellBack = fellBack || result.fellBack
        }
        return PolishResult(text: output.joined(separator: "\n\n"), fellBack: fellBack)
    }

    private func tidy(_ chunk: String, model: SystemLanguageModel, instructions: String, mayRetry: Bool) async -> PolishResult {
        do {
            let inputTokens = try await model.tokenCount(for: chunk)
            let session = LanguageModelSession(model: model, instructions: instructions)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: inputTokens + 150)
            let response = try await session.respond(to: Prompt(chunk), options: options)
            let tidied = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FidelityGuard.accepts(raw: chunk, tidied: tidied) else {
                Log.ai.notice("Fidelity guard rejected a tidied chunk; keeping the raw text")
                return PolishResult(text: chunk, fellBack: true)
            }
            return PolishResult(text: tidied, fellBack: false)
        } catch where mayRetry && ModelStatus.isContextExceeded(error) {
            let (first, second) = Self.halves(of: chunk)
            guard !second.isEmpty else { return PolishResult(text: chunk, fellBack: true) }
            let a = await tidy(first, model: model, instructions: instructions, mayRetry: false)
            let b = await tidy(second, model: model, instructions: instructions, mayRetry: false)
            return PolishResult(text: a.text + " " + b.text, fellBack: a.fellBack || b.fellBack)
        } catch {
            Log.ai.notice("Tidying a chunk failed (\(String(describing: error), privacy: .public)); keeping the raw text")
            return PolishResult(text: chunk, fellBack: true)
        }
    }

    /// Splits at the sentence boundary nearest the middle.
    static func halves(of text: String) -> (String, String) {
        let sentences = Chunker.sentences(in: text)
        if sentences.count > 1 {
            let middle = sentences.count / 2
            return (sentences[..<middle].joined(separator: " "), sentences[middle...].joined(separator: " "))
        }
        let words = text.split(separator: " ")
        let middle = words.count / 2
        return (words[..<middle].joined(separator: " "), words[middle...].joined(separator: " "))
    }
}
