import Foundation
import Testing
@testable import Murmur

@MainActor
struct SettingsStoreTests {
    let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)

    func json(at url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    @Test func firstLaunchCreatesInboxAimedAtDocuments() async throws {
        let directory = Fixtures.temporaryDirectory()
        let store = SettingsStore(directory: directory, homeDirectory: home)
        await store.flush()

        let settings = store.settings
        #expect(settings.projects.map(\.name) == ["Inbox"])
        #expect(settings.projects[0].folderPathHint == "/Users/tester/Documents/Murmur")
        #expect(settings.projects[0].folderBookmark == nil)
        #expect(settings.activeProjectID == settings.projects[0].id)
        #expect(settings.frontMatter.template == FrontMatterPreset.minimal.template)

        let saved = try json(at: store.fileURL)
        #expect(saved["version"] as? Int == 1)
    }

    @Test func missingKeysGetDefaults() throws {
        let directory = Fixtures.temporaryDirectory()
        try Data(#"{"version": 1, "projects": [{"name": "A"}]}"#.utf8).write(to: directory.appending(path: "settings.json"))
        let store = SettingsStore(directory: directory, homeDirectory: home)
        #expect(store.loadWarning == nil)
        #expect(store.settings.projects.map(\.name) == ["A"])
        #expect(store.settings.projects[0].style == .standard)
        #expect(store.settings.noteTypes == ["idea", "decision", "thought", "problem", "progress"])
        #expect(store.settings.ai.tags.maxCount == 3)
    }

    @Test func keepsUnknownKeysAndRemovesClearedOptionals() async throws {
        let directory = Fixtures.temporaryDirectory()
        let id = UUID()
        let file = """
            {"version": 1, "futureKey": {"a": 1}, "activeProjectID": "\(id.uuidString)",
             "ai": {"title": false, "futureAI": "x"},
             "projects": [{"id": "\(id.uuidString)", "name": "A", "defaultNoteType": "idea", "extra": 7}]}
            """
        try Data(file.utf8).write(to: directory.appending(path: "settings.json"))
        let store = SettingsStore(directory: directory, homeDirectory: home)
        #expect(store.settings.ai.title == false)

        store.update { settings in
            settings.projects[0].name = "B"
            settings.projects[0].defaultNoteType = nil
        }
        await store.flush()

        let saved = try json(at: store.fileURL)
        #expect((saved["futureKey"] as? [String: Any])?["a"] as? Int == 1)
        #expect((saved["ai"] as? [String: Any])?["futureAI"] as? String == "x")
        let project = try #require((saved["projects"] as? [[String: Any]])?.first)
        #expect(project["name"] as? String == "B")
        #expect(project["extra"] as? Int == 7)
        #expect(project["defaultNoteType"] == nil)
    }

    @Test func corruptFileIsBackedUpAndDefaultsLoad() throws {
        let directory = Fixtures.temporaryDirectory()
        try Data("{ not json".utf8).write(to: directory.appending(path: "settings.json"))
        let store = SettingsStore(directory: directory, homeDirectory: home)

        #expect(store.loadWarning != nil)
        #expect(store.settings.projects.map(\.name) == ["Inbox"])
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(files.contains { $0.hasPrefix("settings.corrupt-") })
    }

    @Test func savesAreDebounced() async throws {
        let directory = Fixtures.temporaryDirectory()
        let store = SettingsStore(directory: directory, homeDirectory: home, debounce: .milliseconds(50))
        await store.flush()
        store.update { $0.noteTypes = ["a"] }
        store.update { $0.noteTypes = ["b"] }
        try await Task.sleep(for: .milliseconds(300))
        let saved = try json(at: store.fileURL)
        #expect(saved["noteTypes"] as? [String] == ["b"])
    }
}
