import Foundation
import Testing
@testable import Murmur

struct TemplateEditingTests {
    // MARK: Catalog

    @Test func catalogCoversEveryPlaceholder() {
        #expect(PlaceholderCatalog.placeholders.map(\.name) == TemplateContext.knownPlaceholders)
        #expect(PlaceholderCatalog.placeholders.filter(\.isAI).map(\.name) == ["ai_summary", "ai_key_points", "ai_tags"])
        for entry in PlaceholderCatalog.placeholders {
            #expect(TemplateRenderer.soloPlaceholder(entry.insertText)?.name == entry.name)
        }
    }

    @Test func everyCataloguedFilterDoesSomething() {
        let withAI = TemplateContext.sample(withAI: true, style: .standard)
        let withoutAI = TemplateContext.sample(withAI: false, style: .standard)
        let obsidian = TemplateContext.sample(withAI: true, style: .obsidian)
        let probes: [(template: String, context: TemplateContext)] = [
            ("k: {{title%@}}", withAI),
            ("k: {{ai_tags%@}}", withAI),
            ("k: {{ai_tags%@}}", obsidian),
            ("k: {{ai_summary%@}}", withoutAI),
        ]
        for entry in PlaceholderCatalog.filters {
            let filter = entry.name == "default" ? "|default:\"none\"" : entry.insertText
            let changed = probes.contains { probe in
                let renderer = TemplateRenderer(context: probe.context)
                let plain = renderer.renderFrontMatter(probe.template.replacingOccurrences(of: "%@", with: ""), omitEmpty: false)
                let filtered = renderer.renderFrontMatter(probe.template.replacingOccurrences(of: "%@", with: filter), omitEmpty: false)
                return plain != filtered
            }
            #expect(changed, "\(entry.name) changes nothing")
        }
    }

    // MARK: Highlighting

    @Test func highlightsKnownAndUnknownPlaceholders() {
        let text = "a: {{title|lower}}\nb: {{date:YYYY}} {{nope}}\nc: {{ broken"
        let highlights = TemplateEditing.highlights(in: text)
        #expect(highlights == [
            .init(range: 3..<18, isKnown: true),
            .init(range: 22..<35, isKnown: true),
            .init(range: 36..<44, isKnown: false),
        ])
        #expect(TemplateEditing.unknownPlaceholders(in: text + " {{nope}} {{other}}") == ["{{nope}}", "{{other}}"])
    }

    @Test func highlightsCountCharactersNotBytes() {
        let highlights = TemplateEditing.highlights(in: "é👍: {{project}}")
        #expect(highlights == [.init(range: 4..<15, isKnown: true)])
    }

    @Test func parserRangesMatchTokens() {
        let text = "x {{title}} y {{ai_tags|flow}}"
        let ranges = TemplateParser.placeholderRanges(in: text)
        #expect(ranges.map { String(text[$0.range]) } == ["{{title}}", "{{ai_tags|flow}}"])
        #expect(ranges.map(\.placeholder.name) == ["title", "ai_tags"])
    }

    // MARK: Autocomplete

    @Test func completionQueryFindsPartialNames() {
        let text = "title: {{ti"
        #expect(TemplateEditing.completionQuery(text: text, cursor: text.count)
            == .init(kind: .placeholder, prefix: "ti", range: 9..<11))
        #expect(TemplateEditing.completionQuery(text: "a: {{", cursor: 5) == .init(kind: .placeholder, prefix: "", range: 5..<5))

        let filter = "t: {{title|sl"
        #expect(TemplateEditing.completionQuery(text: filter, cursor: filter.count)
            == .init(kind: .filter, prefix: "sl", range: 11..<13))
    }

    @Test func noCompletionOutsideAnOpenPlaceholder() {
        #expect(TemplateEditing.completionQuery(text: "a: {{title}} b", cursor: 14) == nil)
        #expect(TemplateEditing.completionQuery(text: "plain text", cursor: 5) == nil)
        #expect(TemplateEditing.completionQuery(text: "a: {{date:YY", cursor: 12) == nil)
        #expect(TemplateEditing.completionQuery(text: "a: {{ti\nb", cursor: 9) == nil)
    }

    @Test func completionsFilterTheCatalog() {
        let query = TemplateEditing.CompletionQuery(kind: .placeholder, prefix: "ai_", range: 0..<3)
        #expect(TemplateEditing.completions(for: query).map(\.name) == ["ai_summary", "ai_key_points", "ai_tags"])
        let filters = TemplateEditing.CompletionQuery(kind: .filter, prefix: "f", range: 0..<1)
        #expect(TemplateEditing.completions(for: filters).map(\.name) == ["flow", "first"])
    }

    @Test func completingClosesThePlaceholder() throws {
        let text = "title: {{ti"
        let query = try #require(TemplateEditing.completionQuery(text: text, cursor: text.count))
        let title = try #require(PlaceholderCatalog.placeholders.first { $0.name == "title" })
        let result = TemplateEditing.complete(title, query: query, in: text)
        #expect(result.text == "title: {{title}}")
        #expect(result.cursor == result.text.count)
    }

    @Test func completingKeepsAnExistingClose() throws {
        let text = "title: {{ti}}"
        let query = try #require(TemplateEditing.completionQuery(text: text, cursor: 11))
        let title = try #require(PlaceholderCatalog.placeholders.first { $0.name == "title" })
        let result = TemplateEditing.complete(title, query: query, in: text)
        #expect(result.text == "title: {{title}}")
        #expect(result.cursor == 14)
    }

    @Test func completingDefaultLeavesTheCursorInTheQuotes() throws {
        let text = "t: {{title|de"
        let query = try #require(TemplateEditing.completionQuery(text: text, cursor: text.count))
        let entry = try #require(PlaceholderCatalog.filters.first { $0.name == "default" })
        let result = TemplateEditing.complete(entry, query: query, in: text)
        #expect(result.text == "t: {{title|default:\"\"}}")
        #expect(result.cursor == result.text.count - 3)
    }

    @Test func insertMenuPlacesFiltersInsideThePlaceholder() throws {
        let slug = try #require(PlaceholderCatalog.filters.first { $0.name == "slug" })
        let text = "t: {{title}}"
        let result = TemplateEditing.insert(slug, into: text, cursor: text.count)
        #expect(result.text == "t: {{title|slug}}")
        #expect(result.cursor == 15)

        let project = try #require(PlaceholderCatalog.placeholders.first { $0.name == "project" })
        #expect(TemplateEditing.insert(project, into: "p: ", cursor: 3) == ("p: {{project}}", 14))
    }

    // MARK: Preview samples

    @Test func presetsRenderValidYAMLWithBothSamples() {
        for preset in FrontMatterPreset.allCases {
            for withAI in [true, false] {
                for style in NoteStyleKind.allCases {
                    let result = FrontMatterBuilder(
                        globalTemplate: preset.template, projectTemplate: "", mode: .inherit, omitEmpty: true, mergeLists: []
                    ).build(context: .sample(withAI: withAI, style: style))
                    if case .invalid(_, let error) = result {
                        Issue.record("\(preset) invalid (withAI: \(withAI), \(style)): \(error)")
                    }
                }
            }
        }
    }

    @Test func aiUnavailableSampleDropsAIKeys() {
        let template = "title: {{title}}\nsummary: {{ai_summary}}\ntags:\n  - voice-note\n  - {{ai_tags}}\ntype: {{type}}"
        let builder = FrontMatterBuilder(globalTemplate: template, projectTemplate: "", mode: .inherit, omitEmpty: true, mergeLists: [])
        let london = TimeZone(identifier: "Europe/London")!
        #expect(builder.build(context: .sample(withAI: false, style: .obsidian, timeZone: london)) == .valid("""
            title: Voice note 14:32
            tags:
              - voice-note
            """))
        guard case .valid(let withAI) = builder.build(context: .sample(withAI: true, style: .obsidian, timeZone: london)) else {
            Issue.record("expected valid")
            return
        }
        #expect(withAI.contains("summary: ") && withAI.contains("  - sqlite") && withAI.contains("type: decision"))
    }

    @Test(arguments: [
        ("title: ok\nbad line\nx: 1", 2),           // error noticed on the next line
        ("title: ok\nx: 1\nbad line", 3),           // ...or at the end of the text
        ("title: ok\nbad: [unclosed\nx: 1", 2),
        ("title: ok\nbad: \"unclosed\nx: 1", 2),
        ("title: ok\nx: a: b\ny: 1", 2),            // no context: the problem mark is right
        ("title: ok\n- item", 2),
        ("title: ok\nx: 1\ntitle: again", 3),       // duplicate key
    ])
    func invalidYAMLErrorNamesTheLine(yaml: String, line: Int) {
        guard case .invalid(_, let error) = FrontMatterBuilder.validate(yaml) else {
            Issue.record("expected invalid")
            return
        }
        #expect(error.hasPrefix("line \(line): "), "\(error)")
    }

    // MARK: Used AI values

    @Test func usedAIValuesSummary() {
        func summary(template: String, ai: AISettings = AISettings()) -> String {
            MetadataRequirements(
                ai: ai, noteType: .auto, projectDefaultType: nil, noteTypes: ["idea"],
                effectiveTemplate: template, filenamePattern: "", timelineEnabled: false
            ).summaryText
        }
        #expect(summary(template: "created: {{datetime}}")
            == "AI will generate: title, summary, key points. Not generated: type, tags.")
        #expect(summary(template: "type: {{type}}\ntags: {{ai_tags}}")
            == "AI will generate: title, summary, key points, type, tags.")

        var off = AISettings()
        off.title = false
        off.body = .init(summary: false, keyPoints: false)
        #expect(summary(template: "", ai: off) == "AI won't generate anything. Not generated: title, summary, key points, type, tags.")
    }
}
