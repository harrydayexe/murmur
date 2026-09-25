import Foundation

/// Front matter presets (SPEC §5.3.2). None of them use `ai_` placeholders.
enum FrontMatterPreset: String, CaseIterable, Sendable {
    case none
    case minimal
    case obsidianBasic

    var displayName: String {
        switch self {
        case .none: "None"
        case .minimal: "Minimal"
        case .obsidianBasic: "Obsidian basic"
        }
    }

    var template: String {
        switch self {
        case .none:
            ""
        case .minimal:
            "created: {{datetime}}"
        case .obsidianBasic:
            """
            title: {{title}}
            created: {{datetime}}
            project: "[[{{project}}]]"
            """
        }
    }

    static let `default`: FrontMatterPreset = .minimal
}
