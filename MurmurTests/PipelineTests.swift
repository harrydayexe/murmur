import Foundation
import Synchronization
import Testing
@testable import Murmur

/// Records what the pipeline asked for; optionally inspects the disk when called.
final class FakePolisher: TextPolishing {
    let calls = Mutex(0)
    let result: Result<PolishResult, AIError>
    let onPolish: @Sendable () -> Void

    init(result: Result<PolishResult, AIError>, onPolish: @escaping @Sendable () -> Void = {}) {
        self.result = result
        self.onPolish = onPolish
    }

    func polish(_ text: String, glossary: [String], progress: @escaping @Sendable (Int, Int) async -> Void) async throws -> PolishResult {
        calls.withLock { $0 += 1 }
        onPolish()
        await progress(1, 1)
        return try result.get()
    }
}

final class FakeGenerator: MetadataGenerating {
    let requests = Mutex<[MetadataRequest]>([])
    let result: Result<GeneratedMetadata, AIError>

    init(result: Result<GeneratedMetadata, AIError>) {
        self.result = result
    }

    func generate(_ request: MetadataRequest) async throws -> GeneratedMetadata {
        requests.withLock { $0.append(request) }
        return try result.get()
    }
}

struct PipelineTests {
    let capture = CapturedRecording(
        segments: [
            TranscriptSegment(text: "um so we chose sqlite", start: 0, end: 2),
            TranscriptSegment(text: "because json was fragile", start: 5, end: 7),
        ],
        duration: 7.4,
        audioFile: nil
    )

    func snapshot(folder: URL?, template: String, style: NoteStyleKind = .obsidian, change: (inout AppSettings) -> Void = { _ in }) -> RecordingSnapshot {
        var settings = AppSettings()
        settings.frontMatter.template = template
        settings.recording.locale = "en-GB"
        change(&settings)
        return RecordingSnapshot(
            project: Project(name: "Murmur", folderPathHint: folder?.path() ?? "", style: style),
            settings: settings,
            noteType: .auto,
            startDate: Fixtures.date,
            timeZone: Fixtures.london,
            appVersion: "0.1.0",
            folder: folder
        )
    }

    func pipeline(polisher: FakePolisher, generator: FakeGenerator, unsaved: URL) -> NotePipeline {
        NotePipeline(polisher: polisher, metadata: generator, unsavedRoot: unsaved) { url in
            FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false))
        }
    }

    func markdownFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".md") }.map { folder.appending(path: $0) }
    }

    @Test func rawNoteExistsBeforeTidyingWithAIPlaceholdersOmitted() async throws {
        let folder = Fixtures.temporaryDirectory()
        let seen = Mutex<String?>(nil)
        let polisher = FakePolisher(result: .success(PolishResult(text: "So we chose SQLite because JSON was fragile.", fellBack: false))) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            let note = files.first { $0.hasSuffix(".md") }.flatMap { try? String(contentsOf: folder.appending(path: $0), encoding: .utf8) }
            seen.withLock { $0 = note }
        }
        let generator = FakeGenerator(result: .success(GeneratedMetadata(title: "Chose SQLite", summary: "Picked SQLite.")))
        let template = "created: {{datetime}}\nsummary: {{ai_summary}}\nprocessing: {{processing}}"

        let result = try await pipeline(polisher: polisher, generator: generator, unsaved: Fixtures.temporaryDirectory())
            .run(capture, snapshot: snapshot(folder: folder, template: template))

        let draft = try #require(seen.withLock { $0 })
        #expect(draft.hasPrefix("---\ncreated: 2026-09-25T14:32:05\nprocessing: raw\n---\n\n# Voice note 14:32"))
        #expect(!draft.contains("summary:"))
        #expect(draft.contains("um so we chose sqlite\n\nbecause json was fragile"))

        let final = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(result.noteURL.lastPathComponent == "2026-09-25-1432-chose-sqlite.md")
        #expect(final.hasPrefix("---\ncreated: 2026-09-25T14:32:05\nsummary: Picked SQLite.\nprocessing: tidied\n---\n\n# Chose SQLite"))
        #expect(final.contains("## Transcript\n\nSo we chose SQLite because JSON was fragile."))
        #expect(final.contains("> [!quote]- Raw transcript\n> um so we chose sqlite"))
        #expect(markdownFiles(in: folder).count == 1, "the draft was renamed, not duplicated")
        #expect(result.processing == .tidied)
    }

    @Test func failingAIStillLeavesAValidNote() async throws {
        let folder = Fixtures.temporaryDirectory()
        let polisher = FakePolisher(result: .failure(.unavailable("appleIntelligenceNotEnabled")))
        let generator = FakeGenerator(result: .failure(.unavailable("appleIntelligenceNotEnabled")))

        let result = try await pipeline(polisher: polisher, generator: generator, unsaved: Fixtures.temporaryDirectory())
            .run(capture, snapshot: snapshot(folder: folder, template: FrontMatterPreset.obsidianBasic.template + "\nsummary: {{ai_summary}}"))

        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(result.title == "Voice note 14:32")
        #expect(result.processing == .raw)
        #expect(result.warnings.isEmpty)
        #expect(note.hasPrefix("---\ntitle: Voice note 14:32\ncreated: 2026-09-25T14:32:05\nproject: \"[[Murmur]]\"\n---\n\n# Voice note 14:32"))
        #expect(!note.contains("summary"))
        #expect(!note.contains("Key points"))
    }

    @Test func tagsAreNeverRequestedUnlessTheTemplateAsks() async throws {
        let folder = Fixtures.temporaryDirectory()
        let generator = FakeGenerator(result: .success(GeneratedMetadata(title: "T", tags: ["Swift"])))
        let result = try await pipeline(
            polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: false))),
            generator: generator,
            unsaved: Fixtures.temporaryDirectory()
        ).run(capture, snapshot: snapshot(folder: folder, template: FrontMatterPreset.minimal.template))

        let request = try #require(generator.requests.withLock { $0.first })
        #expect(!request.fields.contains(.tags))
        #expect(!(try String(contentsOf: result.noteURL, encoding: .utf8)).contains("tags"))
    }

    @Test func requestedTagsAreNormalisedAndSpliced() async throws {
        let folder = Fixtures.temporaryDirectory()
        let generator = FakeGenerator(result: .success(GeneratedMetadata(title: "T", tags: ["#Swift UI", "2026", "Audio"])))
        let result = try await pipeline(
            polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: false))),
            generator: generator,
            unsaved: Fixtures.temporaryDirectory()
        ).run(capture, snapshot: snapshot(folder: folder, template: "tags:\n  - voice-note\n  - {{ai_tags}}"))

        #expect(generator.requests.withLock { $0.first?.fields.contains(.tags) } == true)
        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(note.hasPrefix("---\ntags:\n  - voice-note\n  - swift-ui\n  - audio\n---"))
    }

    @Test func noModelCallWhenNothingIsNeeded() async throws {
        let folder = Fixtures.temporaryDirectory()
        let polisher = FakePolisher(result: .success(PolishResult(text: "x", fellBack: false)))
        let generator = FakeGenerator(result: .success(GeneratedMetadata()))
        _ = try await pipeline(polisher: polisher, generator: generator, unsaved: Fixtures.temporaryDirectory())
            .run(capture, snapshot: snapshot(folder: folder, template: "") { settings in
                settings.ai.tidyLevel = .off
                settings.ai.title = false
                settings.ai.body = .init(summary: false, keyPoints: false)
            })
        #expect(polisher.calls.withLock { $0 } == 0)
        #expect(generator.requests.withLock { $0.isEmpty })
    }

    @Test func partialTidyingIsRecorded() async throws {
        let folder = Fixtures.temporaryDirectory()
        let result = try await pipeline(
            polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: true))),
            generator: FakeGenerator(result: .success(GeneratedMetadata())),
            unsaved: Fixtures.temporaryDirectory()
        ).run(capture, snapshot: snapshot(folder: folder, template: "p: {{processing}}"))
        #expect(try String(contentsOf: result.noteURL, encoding: .utf8).hasPrefix("---\np: tidied-partial\n---"))
    }

    @Test func audioIsDeletedOnceTheNoteIsWritten() async throws {
        let folder = Fixtures.temporaryDirectory()
        let audio = Fixtures.temporaryDirectory().appending(path: "capture.caf")
        try Data([1, 2, 3]).write(to: audio)
        var capture = capture
        capture.audioFile = audio

        let result = try await pipeline(
            polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: false))),
            generator: FakeGenerator(result: .success(GeneratedMetadata(title: "Chose SQLite"))),
            unsaved: Fixtures.temporaryDirectory()
        ).run(capture, snapshot: snapshot(folder: folder, template: ""))

        #expect(!FileManager.default.fileExists(atPath: audio.path(percentEncoded: false)))
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(contents == [result.noteURL.lastPathComponent])
    }

    @Test func unreachableFolderFallsBackToUnsaved() async throws {
        let unsaved = Fixtures.temporaryDirectory()
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        let result = try await pipeline(
            polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: false))),
            generator: FakeGenerator(result: .success(GeneratedMetadata())),
            unsaved: unsaved
        ).run(capture, snapshot: snapshot(folder: missing, template: ""))

        #expect(result.savedToFallback)
        #expect(result.noteURL.deletingLastPathComponent().lastPathComponent == "Murmur")
        #expect(result.noteURL.path().hasPrefix(unsaved.path()))
        #expect(!result.warnings.isEmpty)
    }

    @Test func invalidTemplateStillSavesWithWarning() async throws {
        let folder = Fixtures.temporaryDirectory()
        let result = try await pipeline(
            polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: false))),
            generator: FakeGenerator(result: .success(GeneratedMetadata())),
            unsaved: Fixtures.temporaryDirectory()
        ).run(capture, snapshot: snapshot(folder: folder, template: "title: [{{title}}"))

        let note = try String(contentsOf: result.noteURL, encoding: .utf8)
        #expect(note.hasPrefix("%%\nfront matter invalid:"))
        #expect(!result.warnings.isEmpty)
    }

    @Test func collisionsGetSuffixes() async throws {
        let folder = Fixtures.temporaryDirectory()
        let run = {
            try await pipeline(
                polisher: FakePolisher(result: .success(PolishResult(text: "x", fellBack: false))),
                generator: FakeGenerator(result: .success(GeneratedMetadata(title: "Same"))),
                unsaved: Fixtures.temporaryDirectory()
            ).run(capture, snapshot: snapshot(folder: folder, template: ""))
        }
        let first = try await run()
        let second = try await run()
        #expect(first.noteURL.lastPathComponent == "2026-09-25-1432-same.md")
        #expect(second.noteURL.lastPathComponent == "2026-09-25-1432-same-2.md")
    }
}
