import Foundation
import Testing
@testable import Murmur

struct ChunkerTests {
    let wordCount: (String) async -> Int = { $0.split(whereSeparator: \.isWhitespace).count }

    @Test func packsParagraphsUpToBudget() async {
        let text = "one two three four\n\nfive six seven eight\n\nnine ten eleven twelve"
        let chunks = await Chunker.chunks(of: text, budget: 8, tokenCount: wordCount)
        #expect(chunks == ["one two three four\n\nfive six seven eight", "nine ten eleven twelve"])
    }

    @Test func splitsLongParagraphsBySentence() async {
        let paragraph = (1...10).map { "Sentence number \($0)." }.joined(separator: " ")
        let chunks = await Chunker.chunks(of: paragraph, budget: 7, tokenCount: wordCount)
        #expect(chunks.count > 1)
        for chunk in chunks { #expect(await wordCount(chunk) <= 7) }
        #expect(chunks.joined(separator: " ") == paragraph)
    }

    @Test func splitsVeryLongSentencesByWord() async {
        let sentence = (1...20).map { "w\($0)" }.joined(separator: " ")
        let chunks = await Chunker.chunks(of: sentence, budget: 5, tokenCount: wordCount)
        #expect(chunks.count == 4)
        #expect(chunks.joined(separator: " ") == sentence)
    }

    @Test func emptyTextHasNoChunks() async {
        #expect(await Chunker.chunks(of: "  \n\n ", budget: 10, tokenCount: wordCount).isEmpty)
    }
}

struct FidelityGuardTests {
    @Test func acceptsLightTidying() {
        let raw = "um so I uh think we should like use sqlite you know for the cache"
        let tidied = "So I think we should use SQLite for the cache."
        #expect(FidelityGuard.accepts(raw: raw, tidied: tidied))
        #expect(FidelityGuard.accepts(raw: "hello world", tidied: "Hello, world."))
    }

    @Test func rejectsSummaries() {
        let raw = "so we spent the whole morning looking at the cache and in the end we decided that sqlite is better than json because it handles concurrent writes"
        #expect(!FidelityGuard.accepts(raw: raw, tidied: "We chose SQLite for the cache."))
    }

    @Test func rejectsParaphrase() {
        let raw = "the build keeps failing on the continuous integration server every night"
        let tidied = "Nightly CI builds are consistently broken on our automation machine each evening"
        #expect(!FidelityGuard.accepts(raw: raw, tidied: tidied))
    }

    @Test func rejectsAddedContent() {
        let raw = "we moved to sqlite"
        #expect(!FidelityGuard.accepts(raw: raw, tidied: "We moved to SQLite, which is a great embedded database."))
    }

    @Test func dropsFillersWhenCounting() {
        #expect(FidelityGuard.contentWords("Um, you know, I like it") == ["i", "it"])
    }
}

struct MetadataRequirementsTests {
    func fields(
        template: String = "created: {{datetime}}",
        filename: String = "{{date}}-{{title|slug}}",
        noteType: NoteTypeSelection = .auto,
        projectDefault: String? = nil,
        noteTypes: [String] = ["idea", "decision"],
        timeline: Bool = false,
        change: (inout AISettings) -> Void = { _ in }
    ) -> Set<MetadataField> {
        var ai = AISettings()
        change(&ai)
        return MetadataRequirements(
            ai: ai, noteType: noteType, projectDefaultType: projectDefault, noteTypes: noteTypes,
            effectiveTemplate: template, filenamePattern: filename, timelineEnabled: timeline
        ).fields
    }

    @Test func title() {
        #expect(fields().contains(.title))
        #expect(!fields { $0.title = false }.contains(.title))
    }

    @Test func summary() {
        #expect(fields().contains(.summary))
        let off: (inout AISettings) -> Void = { $0.body.summary = false }
        #expect(!fields(change: off).contains(.summary))
        #expect(fields(template: "s: {{ai_summary}}", change: off).contains(.summary))
        #expect(fields(timeline: true, change: off).contains(.summary))
    }

    @Test func keyPoints() {
        #expect(fields().contains(.keyPoints))
        let off: (inout AISettings) -> Void = { $0.body.keyPoints = false }
        #expect(!fields(change: off).contains(.keyPoints))
        #expect(fields(template: "k: {{ai_key_points}}", change: off).contains(.keyPoints))
    }

    @Test func type() {
        #expect(!fields().contains(.type), "not used anywhere")
        #expect(fields(template: "type: {{type}}").contains(.type))
        #expect(fields(filename: "{{type}}-{{title}}").contains(.type))
        #expect(fields(timeline: true).contains(.type))
        #expect(!fields(template: "type: {{type}}", noteTypes: []).contains(.type), "empty type list")
        #expect(!fields(template: "type: {{type}}", noteType: .fixed("idea")).contains(.type), "user picked")
        #expect(!fields(template: "type: {{type}}", projectDefault: "decision").contains(.type), "project default")
        #expect(!fields(template: "type: {{type}}") { $0.classifyType = false }.contains(.type))
    }

    @Test func tags() {
        #expect(!fields().contains(.tags))
        #expect(fields(template: "tags: {{ai_tags}}").contains(.tags))
        #expect(!fields(template: "tags: {{ai_tags}}") { $0.tags.maxCount = 0 }.contains(.tags))
    }

    @Test func nothingNeededWhenAIIsOff() {
        let result = fields { ai in
            ai.title = false
            ai.body = .init(summary: false, keyPoints: false)
        }
        #expect(result.isEmpty)
    }

    @Test func fixedTypePrefersUserPick() {
        let requirements = MetadataRequirements(
            ai: AISettings(), noteType: .fixed("idea"), projectDefaultType: "decision", noteTypes: [],
            effectiveTemplate: "", filenamePattern: "", timelineEnabled: false
        )
        #expect(requirements.fixedType == "idea")
    }
}

struct TagNormalizerTests {
    func normalize(_ tags: [String], change: (inout TagSettings) -> Void = { _ in }) -> [String] {
        var settings = TagSettings()
        settings.maxCount = 10
        change(&settings)
        return TagNormalizer(settings: settings).normalize(tags)
    }

    @Test func lowercasesStripsHashesAndJoinsWords() {
        #expect(normalize(["#Swift UI", "Audio", "2026", "swift-ui", "UX"]) == ["swift-ui", "audio", "ux"])
    }

    @Test func separatorCaseAndPrefix() {
        #expect(normalize(["Swift UI"]) { $0.separator = "_" } == ["swift_ui"])
        #expect(normalize(["Swift UI"]) { $0.case = .asIs } == ["Swift-UI"])
        #expect(normalize(["Swift", "topic/audio"]) { $0.prefix = "topic/" } == ["topic/swift", "topic/audio"])
    }

    @Test func allowedOnlyRejectsOthers() {
        let result = normalize(["Swift", "databases", "UX", "#audio"]) { settings in
            settings.mode = .allowedOnly
            settings.allowed = ["swift", "audio", "ux"]
        }
        #expect(result == ["swift", "ux", "audio"])
    }

    @Test func capsAtMaxCount() {
        #expect(normalize(["a", "b", "c"]) { $0.maxCount = 2 } == ["a", "b"])
        #expect(normalize(["a"]) { $0.maxCount = 0 }.isEmpty)
    }
}

struct TranscriptTests {
    @Test func paragraphsSplitOnLongGaps() {
        let segments = [
            TranscriptSegment(text: " First part.", start: 0, end: 1.5),
            TranscriptSegment(text: "Still first.", start: 2.0, end: 3.0),
            TranscriptSegment(text: "Second paragraph.", start: 5.0, end: 6.0),
            TranscriptSegment(text: "  ", start: 6.0, end: 6.5),
            TranscriptSegment(text: "Third.", start: 9.0, end: 10.0),
        ]
        #expect(TranscriptAssembler.text(from: segments) == "First part. Still first.\n\nSecond paragraph.\n\nThird.")
    }

    @Test func glossaryReplacesWholeWordsCaseInsensitively() {
        let glossary = Glossary(entries: ["Xcode", "swift ui => SwiftUI", "core ml=>Core ML"])
        #expect(glossary.preferred == ["Xcode", "SwiftUI", "Core ML"])
        #expect(glossary.apply(to: "I like Swift UI and swift uikit, and CORE ML.") == "I like SwiftUI and swift uikit, and Core ML.")
    }

    @Test func glossaryIgnoresBlankEntries() {
        let glossary = Glossary(entries: ["", " => x", "  "])
        #expect(glossary.preferred.isEmpty)
        #expect(glossary.replacements.isEmpty)
    }
}
