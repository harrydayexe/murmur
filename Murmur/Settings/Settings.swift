import Foundation

/// The contents of `settings.json` (SPEC §4.1).
struct AppSettings: Codable, Equatable, Sendable {
    var version = 1
    var activeProjectID: UUID?
    var frontMatter = FrontMatterSettings()
    var noteTypes = ["idea", "decision", "thought", "problem", "progress"]
    var projects: [Project] = []
    var recording = RecordingSettings()
    var ai = AISettings()
    var output = OutputSettings()
    var launchAtLogin = false

    var activeProject: Project? {
        projects.first { $0.id == activeProjectID && !$0.archived } ?? projects.first { !$0.archived }
    }

    /// First-launch defaults: one "Inbox" project aimed at `~/Documents/Murmur`, with no folder access yet.
    static func initial(homeDirectory: URL) -> AppSettings {
        let inbox = Project(
            name: "Inbox",
            folderPathHint: homeDirectory.appending(path: "Documents/Murmur").path(percentEncoded: false)
        )
        var settings = AppSettings()
        settings.projects = [inbox]
        settings.activeProjectID = inbox.id
        return settings
    }
}

struct FrontMatterSettings: Codable, Equatable, Sendable {
    var template = FrontMatterPreset.default.template
    var omitEmpty = true
    var mergeLists = ["tags", "aliases"]
}

struct RecordingSettings: Codable, Equatable, Sendable {
    var locale = Locale.current.identifier(.bcp47)
    var maxMinutes = 30
    var inputDeviceUID: String?
}

enum TidyLevel: String, Codable, Sendable {
    case off
    case light
}

struct AISettings: Codable, Equatable, Sendable {
    struct Body: Codable, Equatable, Sendable {
        var summary = true
        var keyPoints = true
    }

    var tidyLevel = TidyLevel.light
    var title = true
    var body = Body()
    var classifyType = true
    var tags = TagSettings()
    var glossary: [String] = []
}

struct TagSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable {
        case free
        case allowedOnly
    }

    enum Case: String, Codable, Sendable {
        case lower
        case asIs
    }

    var maxCount = 3
    var mode = Mode.free
    var allowed: [String] = []
    var prefix = ""
    var `case` = Case.lower
    var separator = "-"
}

struct OutputSettings: Codable, Equatable, Sendable {
    var filenamePattern = "{{date:YYYY-MM-DD}}-{{time:HHmm}}-{{title|slug}}"
    var writeTimeline = true
    var notify = true
}
