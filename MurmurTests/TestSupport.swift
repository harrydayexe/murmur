import Foundation
@testable import Murmur

enum Fixtures {
    static let london = TimeZone(identifier: "Europe/London")!

    /// Friday 25 September 2026, 14:32:05 BST (+01:00).
    static let date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14, minute: 32, second: 5))!
    }()

    static func context(style: NoteStyleKind = .obsidian) -> TemplateContext {
        TemplateContext(
            title: "Chose SQLite over JSON",
            project: "Murmur",
            type: "",
            date: date,
            timeZone: london,
            style: style,
            durationSeconds: 192,
            locale: "en-GB",
            filename: "2026-09-25-1432-chose-sqlite-over-json",
            processing: .tidied,
            appVersion: "0.1.0",
            aiSummary: "Decided to move the cache.",
            aiKeyPoints: ["SQLite is faster", "JSON was fragile"],
            aiTags: ["swift", "audio"]
        )
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "MurmurTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
