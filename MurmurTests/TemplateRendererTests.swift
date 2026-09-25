import Foundation
import Testing
@testable import Murmur

struct DateTokenFormatterTests {
    let formatter = DateTokenFormatter(timeZone: Fixtures.london, locale: Locale(identifier: "en-GB"))

    @Test(arguments: [
        ("YYYY-MM-DD", "2026-09-25"),
        ("dddd D MMMM YYYY", "Friday 25 September 2026"),
        ("ddd, D MMM YY", "Fri, 25 Sep 26"),
        ("M/D", "9/25"),
        ("HH:mm:ss", "14:32:05"),
        ("h:mm A", "2:32 PM"),
        ("hh", "02"),
        ("H", "14"),
        ("Z", "+01:00"),
        ("ZZ", "+0100"),
        ("[week] w", "week 39"),
        ("[YYYY] YYYY", "YYYY 2026"),
        ("YYYY-MM-DDTHH:mm:ss", "2026-09-25T14:32:05"),
    ])
    func formats(format: String, expected: String) {
        #expect(formatter.string(from: Fixtures.date, format: format) == expected)
    }
}

struct TemplateParserTests {
    @Test func parsesPlaceholdersFiltersAndArguments() {
        let tokens = TemplateParser.parse(#"a {{date:D MMMM}} b {{title|slug|default:"x|y"}}"#)
        #expect(tokens.count == 4)
        guard case .placeholder(let date) = tokens[1], case .placeholder(let title) = tokens[3] else {
            Issue.record("expected placeholders")
            return
        }
        #expect(date.name == "date")
        #expect(date.argument == "D MMMM")
        #expect(title.filters == [.init(name: "slug", argument: nil), .init(name: "default", argument: "x|y")])
    }

    @Test func leavesNonPlaceholdersAsLiterals() {
        #expect(TemplateParser.parse("{{ not valid }} and {{") == [.literal("{{ not valid }} and {{")])
    }

    @Test func collectsNames() {
        #expect(TemplateParser.placeholderNames(in: "t: {{title}}\n- {{ai_tags|first}}") == ["title", "ai_tags"])
    }
}

struct TemplateRendererTests {
    func inline(_ template: String, style: NoteStyleKind = .obsidian, change: (inout TemplateContext) -> Void = { _ in }) -> String {
        var context = Fixtures.context(style: style)
        change(&context)
        return TemplateRenderer(context: context).renderInline(template)
    }

    func frontMatter(_ template: String, style: NoteStyleKind = .obsidian, omitEmpty: Bool = true, change: (inout TemplateContext) -> Void = { _ in }) -> String {
        var context = Fixtures.context(style: style)
        change(&context)
        return TemplateRenderer(context: context).renderFrontMatter(template, omitEmpty: omitEmpty)
    }

    // MARK: Placeholders

    @Test(arguments: [
        ("{{title}}", "Chose SQLite over JSON"),
        ("{{project}}", "Murmur"),
        ("{{type}}", ""),
        ("{{date}}", "2026-09-25"),
        ("{{time}}", "14:32"),
        ("{{datetime}}", "2026-09-25T14:32:05"),
        ("{{weekday}}", "Friday"),
        ("{{duration}}", "3m12s"),
        ("{{duration_seconds}}", "192"),
        ("{{locale}}", "en-GB"),
        ("{{filename}}", "2026-09-25-1432-chose-sqlite-over-json"),
        ("{{processing}}", "tidied"),
        ("{{app_version}}", "0.1.0"),
        ("{{ai_summary}}", "Decided to move the cache."),
        ("{{ai_key_points}}", "SQLite is faster, JSON was fragile"),
        ("{{ai_tags}}", "swift, audio"),
        ("{{date:dddd D MMMM YYYY}}", "Friday 25 September 2026"),
        ("{{time:HHmm}}", "1432"),
        ("{{datetime:YYYY}}", "2026"),
    ])
    func everyPlaceholder(template: String, expected: String) {
        #expect(inline(template) == expected)
    }

    @Test func standardStyleDefaults() {
        #expect(inline("{{datetime}}", style: .standard) == "2026-09-25T14:32:05+01:00")
    }

    @Test func shortDurationHasNoMinutes() {
        #expect(inline("{{duration}}") { $0.durationSeconds = 42 } == "42s")
    }

    // MARK: Filters

    @Test(arguments: [
        ("{{title|lower}}", "chose sqlite over json"),
        ("{{title|upper}}", "CHOSE SQLITE OVER JSON"),
        ("{{title|slug}}", "chose-sqlite-over-json"),
        ("{{title|slug|upper}}", "CHOSE-SQLITE-OVER-JSON"),
        ("{{project|wikilink}}", "[[Murmur]]"),
        ("{{project|quote}}", "\"Murmur\""),
        ("{{ai_tags|first}}", "swift"),
        ("{{ai_tags|first|upper}}", "SWIFT"),
        (#"{{type|default:"note"}}"#, "note"),
        (#"{{project|default:"note"}}"#, "Murmur"),
    ])
    func filters(template: String, expected: String) {
        #expect(inline(template) == expected)
    }

    @Test func slugFoldsAccentsAndPunctuation() {
        #expect(TemplateRenderer.slug("Café: déjà vu!  2") == "cafe-deja-vu-2")
    }

    @Test func unknownPlaceholdersStayAsTheyAre() {
        #expect(inline("a {{nope}} {{nope|lower}} b") == "a {{nope}} {{nope|lower}} b")
        #expect(frontMatter("x: {{nope}}") == "x: {{nope}}")
    }

    @Test func newlinesBecomeSpacesInline() {
        #expect(inline("s: {{ai_summary}}") { $0.aiSummary = "one\ntwo" } == "s: one two")
    }

    // MARK: Front matter substitution

    @Test func wholeScalarIsQuotedOnlyWhenNeeded() {
        #expect(frontMatter("title: {{title}}") == "title: Chose SQLite over JSON")
        #expect(frontMatter("title: {{title}}") { $0.title = "Plan: v2" } == #"title: "Plan: v2""#)
        #expect(frontMatter("title: {{title}}") { $0.title = "yes" } == #"title: "yes""#)
        #expect(frontMatter("title: {{title}}") { $0.title = "#hash" } == ##"title: "#hash""##)
        #expect(frontMatter("created: {{datetime}}") == "created: 2026-09-25T14:32:05")
    }

    @Test func insideQuotesEscapes() {
        let result = frontMatter(#"project: "[[{{project}}]]""#) { $0.project = #"My "big" \app"# }
        #expect(result == #"project: "[[My \"big\" \\app]]""#)
    }

    @Test func wholeListUsesStyleLayout() {
        #expect(frontMatter("tags: {{ai_tags}}", style: .obsidian) == "tags:\n  - swift\n  - audio")
        #expect(frontMatter("tags: {{ai_tags}}", style: .standard) == "tags: [swift, audio]")
        #expect(frontMatter("tags: {{ai_tags|flow}}", style: .obsidian) == "tags: [swift, audio]")
        #expect(frontMatter("tags: {{ai_tags|block}}", style: .standard) == "tags:\n  - swift\n  - audio")
    }

    @Test func listSpliceMixesFixedAndAITags() {
        let template = "tags:\n  - voice-note\n  - {{ai_tags}}"
        #expect(frontMatter(template) == "tags:\n  - voice-note\n  - swift\n  - audio")
    }

    @Test func literalSubstitution() {
        #expect(frontMatter("note: {{title}} ({{duration}})") == "note: Chose SQLite over JSON (3m12s)")
    }

    @Test func stripsFencesAndKeepsCommentsAndOrder() {
        let template = "---\n# mine\nz: 1\ncreated: {{date}}\na: 2\n---\n"
        #expect(frontMatter(template) == "# mine\nz: 1\ncreated: 2026-09-25\na: 2")
    }

    // MARK: omitEmpty

    @Test func omitEmptyDropsEmptyScalarsListsAndItems() {
        let template = "created: {{date}}\nsummary: {{ai_summary}}\ntype: {{type}}\nlabel: \"{{type}}\"\ntags: {{ai_tags}}\nkeep:\n  - fixed\n  - {{ai_tags}}\ngone:\n  - {{ai_tags}}"
        let result = frontMatter(template) { $0.aiSummary = ""; $0.aiTags = [] }
        #expect(result == "created: 2026-09-25\nkeep:\n  - fixed")
    }

    @Test func omitEmptyDropsListsOfEmptyItems() {
        #expect(frontMatter("tags: {{ai_tags}}") { $0.aiTags = ["", ""] } == "")
    }

    @Test func withoutOmitEmptyKeysStay() {
        let template = "summary: {{ai_summary}}\ntags: {{ai_tags}}"
        let result = frontMatter(template, omitEmpty: false) { $0.aiSummary = ""; $0.aiTags = [] }
        #expect(result == "summary:\ntags: []")
    }

    @Test func mixedValueWithTextIsKeptWhenPlaceholderEmpty() {
        #expect(frontMatter(#"up: "[[{{type}}]]""#) == #"up: "[[]]""#)
    }
}
