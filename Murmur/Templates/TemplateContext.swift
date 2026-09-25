import Foundation

/// `standard` or `obsidian`. Changes body markup and placeholder default formats, never front matter keys.
enum NoteStyleKind: String, Codable, Sendable, CaseIterable {
    case standard
    case obsidian
}

enum ProcessingStatus: String, Sendable {
    case tidied
    case tidiedPartial = "tidied-partial"
    case raw
}

/// A value a placeholder resolves to.
enum TemplateValue: Equatable, Sendable {
    case scalar(String)
    case list([String])

    var isEmpty: Bool {
        switch self {
        case .scalar(let value): value.isEmpty
        case .list(let items): items.allSatisfy(\.isEmpty)
        }
    }

    /// Scalars as they are; lists joined with `, `.
    var inlineText: String {
        switch self {
        case .scalar(let value): value
        case .list(let items): items.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }
}

/// Everything a template can refer to. Pure data.
struct TemplateContext: Sendable {
    var title: String
    var project: String
    var type: String = ""
    /// Recording start.
    var date: Date
    var timeZone: TimeZone = .current
    var style: NoteStyleKind = .standard
    var durationSeconds: Int = 0
    var locale: String = "en-GB"
    var filename: String = ""
    var processing: ProcessingStatus = .raw
    var appVersion: String = ""
    var aiSummary: String = ""
    var aiKeyPoints: [String] = []
    var aiTags: [String] = []

    static let knownPlaceholders: [String] = [
        "title", "project", "type", "date", "time", "datetime", "weekday",
        "duration", "duration_seconds", "locale", "filename",
        "processing", "app_version", "ai_summary", "ai_key_points", "ai_tags",
    ]

    /// The value for a placeholder, or nil if the name is unknown.
    func value(for name: String, argument: String?) -> TemplateValue? {
        let dates = DateTokenFormatter(timeZone: timeZone, locale: Locale(identifier: locale))
        switch name {
        case "title": return .scalar(title)
        case "project": return .scalar(project)
        case "type": return .scalar(type)
        case "date":
            return .scalar(dates.string(from: date, format: argument ?? DateTokenFormatter.dateFormat))
        case "time":
            return .scalar(dates.string(from: date, format: argument ?? DateTokenFormatter.timeFormat))
        case "datetime":
            let fallback = style == .obsidian ? DateTokenFormatter.obsidianDateTimeFormat : DateTokenFormatter.isoDateTimeFormat
            return .scalar(dates.string(from: date, format: argument ?? fallback))
        case "weekday":
            return .scalar(dates.string(from: date, format: argument ?? DateTokenFormatter.weekdayFormat))
        case "duration":
            let minutes = durationSeconds / 60, seconds = durationSeconds % 60
            return .scalar(minutes > 0 ? "\(minutes)m\(seconds)s" : "\(seconds)s")
        case "duration_seconds": return .scalar(String(durationSeconds))
        case "locale": return .scalar(locale)
        case "filename": return .scalar(filename)
        case "processing": return .scalar(processing.rawValue)
        case "app_version": return .scalar(appVersion)
        case "ai_summary": return .scalar(aiSummary)
        case "ai_key_points": return .list(aiKeyPoints)
        case "ai_tags": return .list(aiTags)
        default: return nil
        }
    }
}
