import Foundation

/// A note's content before it becomes Markdown.
struct NoteDocument: Equatable, Sendable {
    var frontMatter: FrontMatterResult
    var title: String
    /// Empty when summaries are off or generation failed.
    var summary = ""
    var keyPoints: [String] = []
    var transcript: String
    var rawTranscript: String
}

/// Renders a note's Markdown in `standard` or `obsidian` style (SPEC §5.2, §5.4). Pure.
/// Disabled or failed sections are left out, and there are never empty headings.
struct NoteStyle: Sendable {
    var kind: NoteStyleKind

    func render(_ note: NoteDocument) -> String {
        var sections: [String] = []

        switch note.frontMatter {
        case .none:
            break
        case .valid(let yaml):
            sections.append("---\n\(yaml)\n---")
        case .invalid(let rendered, let error):
            sections.append(invalidFrontMatterComment(rendered: rendered, error: error))
        }

        sections.append("# \(TemplateRenderer.singleLine(note.title))")

        let summary = note.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { sections.append(summaryBlock(summary)) }

        let keyPoints = note.keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !keyPoints.isEmpty { sections.append(keyPointsBlock(keyPoints)) }

        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        sections.append("## Transcript\n\n" + (transcript.isEmpty ? "_No speech was transcribed._" : transcript))

        let raw = note.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { sections.append(rawTranscriptBlock(raw)) }

        return sections.joined(separator: "\n\n") + "\n"
    }

    func invalidFrontMatterComment(rendered: String, error: String) -> String {
        switch kind {
        case .obsidian:
            let safe = rendered.replacingOccurrences(of: "%%", with: "% %")
            return "%%\nfront matter invalid: \(error)\n\(safe)\n%%"
        case .standard:
            let safe = rendered.replacingOccurrences(of: "-->", with: "-- >")
            return "<!--\nfront matter invalid: \(error)\n\(safe)\n-->"
        }
    }

    private func summaryBlock(_ summary: String) -> String {
        switch kind {
        case .obsidian: "> [!summary] Summary (AI-generated)\n" + quoted(summary)
        case .standard: "> **Summary** *(AI-generated)*: " + TemplateRenderer.singleLine(summary)
        }
    }

    private func keyPointsBlock(_ points: [String]) -> String {
        let bullets = points.map { "- " + TemplateRenderer.singleLine($0) }.joined(separator: "\n")
        switch kind {
        case .obsidian: return "> [!note]- Key points (AI-generated)\n" + quoted(bullets)
        case .standard: return "**Key points** *(AI-generated)*\n\n" + bullets
        }
    }

    private func rawTranscriptBlock(_ raw: String) -> String {
        switch kind {
        case .obsidian:
            "> [!quote]- Raw transcript\n" + quoted(raw)
        case .standard:
            "<details>\n<summary>Raw transcript</summary>\n\n\(raw)\n\n</details>"
        }
    }

    /// Prefixes every line with `> ` (blank lines become `>`).
    private func quoted(_ text: String) -> String {
        text.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
    }
}
