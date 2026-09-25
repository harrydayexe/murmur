import Foundation

/// Note filenames from `output.filenamePattern` (SPEC §5.1). Pure.
enum Filename {
    static let maxLength = 100
    private static let forbidden = CharacterSet(charactersIn: "[]#^|\\/:").union(.controlCharacters)

    /// Renders the pattern and cleans the result. Returns the name without extension.
    static func render(pattern: String, context: TemplateContext) -> String {
        var context = context
        if TemplateRenderer.slug(context.title).isEmpty { context.title = "note" }
        return clean(TemplateRenderer(context: context).renderInline(pattern))
    }

    static func clean(_ name: String) -> String {
        var cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { !forbidden.contains($0) }))
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.count > maxLength { cleaned = String(cleaned.prefix(maxLength)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "note" : cleaned
    }

    /// `base`, then `base-2`, `base-3`, … until `isTaken` returns false.
    static func unique(_ base: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(base) else { return base }
        var counter = 2
        while isTaken("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }
}
