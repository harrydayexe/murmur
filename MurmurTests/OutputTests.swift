import Foundation
import Testing
@testable import Murmur

struct FilenameTests {
    let pattern = "{{date:YYYY-MM-DD}}-{{time:HHmm}}-{{title|slug}}"

    @Test func defaultPattern() {
        #expect(Filename.render(pattern: pattern, context: Fixtures.context()) == "2026-09-25-1432-chose-sqlite-over-json")
    }

    @Test func emptyTitleFallsBackToNote() {
        var context = Fixtures.context()
        context.title = ""
        #expect(Filename.render(pattern: pattern, context: context) == "2026-09-25-1432-note")
        context.title = "!!!"
        #expect(Filename.render(pattern: pattern, context: context) == "2026-09-25-1432-note")
    }

    @Test func cleansForbiddenCharacters() {
        #expect(Filename.clean("a[b]c#d^e|f\\g/h:i\u{7}j") == "abcdefghij")
        #expect(Filename.clean("..hidden") == "hidden")
        #expect(Filename.clean("///") == "note")
    }

    @Test func capsLength() {
        #expect(Filename.clean(String(repeating: "a", count: 150)).count == 100)
    }

    @Test func collisionsGetSuffixes() {
        let taken: Set<String> = ["x", "x-2"]
        #expect(Filename.unique("x") { taken.contains($0) } == "x-3")
        #expect(Filename.unique("y") { taken.contains($0) } == "y")
    }
}

struct NoteStyleTests {
    let document = NoteDocument(
        frontMatter: .valid("created: 2026-09-25"),
        title: "Chose SQLite",
        summary: "Moved the cache.",
        keyPoints: ["Faster", "Simpler"],
        audioFilename: "note one.m4a",
        transcript: "We chose SQLite.\n\nIt is faster.",
        rawTranscript: "we chose sqlite\n\nit is faster"
    )

    @Test func standardBody() {
        let expected = """
            ---
            created: 2026-09-25
            ---

            # Chose SQLite

            > **Summary** *(AI-generated)*: Moved the cache.

            **Key points** *(AI-generated)*

            - Faster
            - Simpler

            [Audio](audio/note%20one.m4a)

            ## Transcript

            We chose SQLite.

            It is faster.

            <details>
            <summary>Raw transcript</summary>

            we chose sqlite

            it is faster

            </details>

            """
        #expect(NoteStyle(kind: .standard).render(document) == expected)
    }

    @Test func obsidianBody() {
        let expected = """
            ---
            created: 2026-09-25
            ---

            # Chose SQLite

            > [!summary] Summary (AI-generated)
            > Moved the cache.

            > [!note]- Key points (AI-generated)
            > - Faster
            > - Simpler

            ![[note one.m4a]]

            ## Transcript

            We chose SQLite.

            It is faster.

            > [!quote]- Raw transcript
            > we chose sqlite
            >
            > it is faster

            """
        #expect(NoteStyle(kind: .obsidian).render(document) == expected)
    }

    @Test func leavesOutEmptySectionsAndFrontMatter() {
        var note = document
        note.frontMatter = .none
        note.summary = ""
        note.keyPoints = []
        note.audioFilename = ""
        let rendered = NoteStyle(kind: .obsidian).render(note)
        #expect(rendered.hasPrefix("# Chose SQLite\n\n## Transcript"))
        #expect(!rendered.contains("Summary"))
        #expect(!rendered.contains("Key points"))
        #expect(!rendered.contains("---"))
    }

    @Test func invalidFrontMatterGoesToAComment() {
        var note = document
        note.frontMatter = .invalid(rendered: "title: [oops", error: "bad")
        #expect(NoteStyle(kind: .obsidian).render(note).hasPrefix("%%\nfront matter invalid: bad\ntitle: [oops\n%%\n\n# Chose SQLite"))
        #expect(NoteStyle(kind: .standard).render(note).hasPrefix("<!--\nfront matter invalid: bad\ntitle: [oops\n-->\n\n# Chose SQLite"))
    }

    @Test func emptyTranscriptSaysSo() {
        var note = document
        note.transcript = ""
        note.rawTranscript = ""
        let rendered = NoteStyle(kind: .standard).render(note)
        #expect(rendered.contains("## Transcript\n\n_No speech was transcribed._"))
        #expect(!rendered.contains("Raw transcript"))
    }
}

struct SaveLocationTests {
    let root = URL(filePath: "/tmp/unsaved", directoryHint: .isDirectory)
    let folder = URL(filePath: "/tmp/project", directoryHint: .isDirectory)

    @Test func usesWritableProjectFolder() {
        let result = SaveLocation.resolve(projectFolder: folder, projectName: "P", unsavedRoot: root) { _ in true }
        #expect(result.folder == folder)
        #expect(!result.isFallback)
    }

    @Test func fallsBackWhenUnwritableOrMissing() {
        let unwritable = SaveLocation.resolve(projectFolder: folder, projectName: "My/Project", unsavedRoot: root) { _ in false }
        #expect(unwritable.isFallback)
        #expect(unwritable.folder.lastPathComponent == "MyProject")
        #expect(unwritable.folder.deletingLastPathComponent().path() == root.path())

        let missing = SaveLocation.resolve(projectFolder: nil, projectName: "P", unsavedRoot: root) { _ in true }
        #expect(missing.isFallback)
    }
}

struct VaultDetectorTests {
    @Test func findsNearestVault() {
        let existing: Set<String> = ["/Users/me/Vault/.obsidian"]
        let root = VaultDetector.vaultRoot(for: URL(filePath: "/Users/me/Vault/Projects/Murmur/Log")) {
            existing.contains($0.path(percentEncoded: false).trimmingSuffix("/"))
        }
        #expect(root?.path(percentEncoded: false).trimmingSuffix("/") == "/Users/me/Vault")
    }

    @Test func returnsNilOutsideVaults() {
        #expect(VaultDetector.vaultRoot(for: URL(filePath: "/Users/me/Notes")) { _ in false } == nil)
    }

    /// Open panels return directory URLs; walking up from one must still stop at `/`.
    @Test func stopsAtRootForDirectoryURLs() {
        var checked: [String] = []
        let root = VaultDetector.vaultRoot(for: URL(filePath: "/Users/me/Documents/", directoryHint: .isDirectory)) {
            checked.append($0.path(percentEncoded: false))
            return false
        }
        #expect(root == nil)
        #expect(checked == ["/Users/me/Documents/.obsidian/", "/Users/me/.obsidian/", "/Users/.obsidian/", "/.obsidian/"])
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
