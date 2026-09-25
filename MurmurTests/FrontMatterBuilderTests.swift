import Foundation
import Testing
@testable import Murmur

struct FrontMatterBuilderTests {
    func build(
        global: String,
        project: String = "",
        mode: FrontMatterMode = .inherit,
        style: NoteStyleKind = .obsidian
    ) -> FrontMatterResult {
        FrontMatterBuilder(globalTemplate: global, projectTemplate: project, mode: mode, omitEmpty: true, mergeLists: ["tags", "aliases"])
            .build(context: Fixtures.context(style: style))
    }

    // MARK: Principles

    @Test func emptyTemplateGivesNoFrontMatter() {
        #expect(build(global: "") == .none)
        #expect(build(global: "---\n---\n") == .none)
        #expect(build(global: "summary: {{ai_summary}}") == .valid("summary: Decided to move the cache."))
    }

    @Test func presetsNeverUseAIPlaceholders() {
        for preset in FrontMatterPreset.allCases {
            #expect(!preset.template.contains("ai_"), "\(preset) uses an AI placeholder")
        }
        #expect(FrontMatterPreset.default == .minimal)
    }

    @Test func presetsRender() {
        #expect(build(global: FrontMatterPreset.none.template) == .none)
        #expect(build(global: FrontMatterPreset.minimal.template) == .valid("created: 2026-09-25T14:32:05"))
        #expect(build(global: FrontMatterPreset.obsidianBasic.template) == .valid("""
            title: Chose SQLite over JSON
            created: 2026-09-25T14:32:05
            project: "[[Murmur]]"
            audio: "[[x.m4a]]"
            """))
    }

    // MARK: Modes

    @Test func inheritUsesGlobal() {
        #expect(build(global: "a: 1", project: "b: 2", mode: .inherit) == .valid("a: 1"))
    }

    @Test func overrideUsesProjectOnly() {
        #expect(build(global: "a: 1", project: "b: 2", mode: .override) == .valid("b: 2"))
        #expect(build(global: "a: 1", project: "", mode: .override) == .none)
    }

    @Test func appendWithoutCollisionsKeepsTextVerbatim() {
        let result = build(global: "# global\ncreated: {{date}}", project: "# project\nstatus: draft", mode: .append)
        #expect(result == .valid("# global\ncreated: 2026-09-25\n# project\nstatus: draft"))
    }

    @Test func appendMergesCollisionsStructurally() {
        let global = "title: {{title}}\ntags:\n  - voice-note\ncreated: {{date}}"
        let project = "title: Override\ntags: [project-x, voice-note]\nstatus: draft"
        #expect(build(global: global, project: project, mode: .append, style: .obsidian) == .valid("""
            title: Override
            tags:
              - voice-note
              - project-x
            created: 2026-09-25
            status: draft
            """))
        #expect(build(global: global, project: project, mode: .append, style: .standard) == .valid("""
            title: Override
            tags: [voice-note, project-x]
            created: 2026-09-25
            status: draft
            """))
    }

    @Test func mergeQuotesWikilinksAndKeepsTypes() {
        let global = "up: \"[[Home]]\"\ncount: 3\nflag: true\nid: \"42\""
        let project = "up: \"[[Project]]\""
        #expect(build(global: global, project: project, mode: .append) == .valid("""
            up: "[[Project]]"
            count: 3
            flag: true
            id: "42"
            """))
    }

    // MARK: Validation

    @Test func invalidYAMLIsReported() {
        guard case .invalid(let rendered, let error) = build(global: "title: [unclosed\nx: {{date}}") else {
            Issue.record("expected invalid")
            return
        }
        #expect(rendered == "title: [unclosed\nx: 2026-09-25")
        #expect(!error.isEmpty)
    }

    @Test func nonMappingIsInvalid() {
        guard case .invalid = build(global: "- just\n- a list") else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func effectiveTemplateFollowsMode() {
        let builder = { (mode: FrontMatterMode) in
            FrontMatterBuilder(globalTemplate: "g", projectTemplate: "p", mode: mode, omitEmpty: true, mergeLists: []).effectiveTemplate
        }
        #expect(builder(.inherit) == "g")
        #expect(builder(.override) == "p")
        #expect(builder(.append) == "g\np")
    }
}
