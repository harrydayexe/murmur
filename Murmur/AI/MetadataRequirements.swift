import Foundation

enum MetadataField: String, CaseIterable, Sendable {
    case title
    case summary
    case keyPoints
    case type
    case tags
}

/// The note type chosen in the popover.
enum NoteTypeSelection: Equatable, Hashable, Sendable {
    case auto
    case fixed(String)
}

/// Works out which AI values are actually used, so nothing else is generated (SPEC §6.5). Pure.
struct MetadataRequirements: Sendable {
    var ai: AISettings
    var noteType: NoteTypeSelection
    var projectDefaultType: String?
    var noteTypes: [String]
    var effectiveTemplate: String
    var filenamePattern: String
    var timelineEnabled: Bool

    var fields: Set<MetadataField> {
        let templateNames = TemplateParser.placeholderNames(in: effectiveTemplate)
        let filenameNames = TemplateParser.placeholderNames(in: filenamePattern)
        var fields = Set<MetadataField>()

        // The body heading always uses the title, so it's needed whenever AI titles are on.
        if ai.title { fields.insert(.title) }

        if ai.body.summary || templateNames.contains("ai_summary") || timelineEnabled {
            fields.insert(.summary)
        }

        if ai.body.keyPoints || templateNames.contains("ai_key_points") {
            fields.insert(.keyPoints)
        }

        let typeUsed = templateNames.contains("type") || filenameNames.contains("type") || timelineEnabled
        let hasDefaultType = !(projectDefaultType ?? "").isEmpty
        if noteType == .auto, !hasDefaultType, ai.classifyType, !noteTypes.isEmpty, typeUsed {
            fields.insert(.type)
        }

        if templateNames.contains("ai_tags"), ai.tags.maxCount > 0 {
            fields.insert(.tags)
        }
        return fields
    }

    /// The type to use without asking the model: the user's pick, then the project default.
    var fixedType: String? {
        if case .fixed(let type) = noteType { return type }
        if let projectDefaultType, !projectDefaultType.isEmpty { return projectDefaultType }
        return nil
    }

    /// For the Used AI values panel, e.g. "AI will generate: title, summary. Not generated: key points, type, tags."
    var summaryText: String {
        let fields = self.fields
        let used = MetadataField.allCases.filter { fields.contains($0) }.map(\.displayName)
        let unused = MetadataField.allCases.filter { !fields.contains($0) }.map(\.displayName)
        var parts = [used.isEmpty ? "AI won't generate anything." : "AI will generate: \(used.joined(separator: ", "))."]
        if !unused.isEmpty { parts.append("Not generated: \(unused.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }
}

extension MetadataField {
    var displayName: String {
        switch self {
        case .title: "title"
        case .summary: "summary"
        case .keyPoints: "key points"
        case .type: "type"
        case .tags: "tags"
        }
    }
}
