import Foundation
import Yams

enum FrontMatterMode: String, Codable, Sendable, CaseIterable {
    case inherit
    case override
    case append
}

enum FrontMatterResult: Equatable, Sendable {
    /// The effective template rendered empty: no front matter block.
    case none
    /// Valid YAML, without `---` fences.
    case valid(String)
    /// Rendered text that failed YAML validation. It goes into a body comment instead.
    case invalid(rendered: String, error: String)
}

/// Builds a note's front matter from the global and project templates (SPEC §5.3.2, §5.3.4). Pure.
struct FrontMatterBuilder: Sendable {
    var globalTemplate: String
    var projectTemplate: String
    var mode: FrontMatterMode
    var omitEmpty: Bool
    var mergeLists: [String]

    /// The template text that applies to notes, for scanning which placeholders are used.
    var effectiveTemplate: String {
        switch mode {
        case .inherit: globalTemplate
        case .override: projectTemplate
        case .append: [globalTemplate, projectTemplate].joined(separator: "\n")
        }
    }

    func build(context: TemplateContext) -> FrontMatterResult {
        let renderer = TemplateRenderer(context: context)
        let text: String
        switch mode {
        case .inherit:
            text = renderer.renderFrontMatter(globalTemplate, omitEmpty: omitEmpty)
        case .override:
            text = renderer.renderFrontMatter(projectTemplate, omitEmpty: omitEmpty)
        case .append:
            let global = renderer.renderFrontMatter(globalTemplate, omitEmpty: omitEmpty)
            let project = renderer.renderFrontMatter(projectTemplate, omitEmpty: omitEmpty)
            text = merge(global, project, style: context.style)
        }
        return Self.validate(text)
    }

    static func validate(_ text: String) -> FrontMatterResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
        do {
            let node = try Yams.compose(yaml: text)
            switch node {
            case .some(.mapping), .none: return .valid(text)
            default: return .invalid(rendered: text, error: "front matter must be a set of `key: value` lines")
            }
        } catch {
            return .invalid(rendered: text, error: Self.describe(error, in: text))
        }
    }

    /// Joins global and project front matter. Colliding top-level keys are merged structurally;
    /// otherwise the rendered text is kept exactly, preserving order and comments.
    private func merge(_ global: String, _ project: String, style: NoteStyleKind) -> String {
        let globalTrimmed = global.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectTrimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        if globalTrimmed.isEmpty { return project }
        if projectTrimmed.isEmpty { return global }

        let collisions = Self.topLevelKeys(global).intersection(Self.topLevelKeys(project))
        let concatenated = global + "\n" + project
        guard !collisions.isEmpty,
              let globalPairs = Self.parseMapping(global),
              let projectPairs = Self.parseMapping(project) else {
            // No collisions, or one side is invalid: keep the text; validation reports any problem.
            return concatenated
        }

        var merged = globalPairs
        for (key, value) in projectPairs {
            if let index = merged.firstIndex(where: { $0.key == key }) {
                if mergeLists.contains(key) {
                    merged[index].value = Self.mergeAsLists(merged[index].value, value)
                } else {
                    merged[index].value = value
                }
            } else {
                merged.append((key, value))
            }
        }
        return YAMLEmitter.emit(merged, listLayout: style == .obsidian ? .block : .flow)
    }

    private static func mergeAsLists(_ first: YAMLValue, _ second: YAMLValue) -> YAMLValue {
        func items(_ value: YAMLValue) -> [YAMLValue] {
            switch value {
            case .sequence(let values): values
            case .scalar(let text, _) where text.isEmpty: []
            default: [value]
            }
        }
        var result: [YAMLValue] = []
        for item in items(first) + items(second) where !result.contains(item) {
            result.append(item)
        }
        return .sequence(result)
    }

    static func topLevelKeys(_ text: String) -> Set<String> {
        var keys = Set<String>()
        for line in text.components(separatedBy: "\n") {
            guard let (indent, key, _) = TemplateRenderer.splitKeyValue(line), indent.isEmpty else { continue }
            keys.insert(key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        }
        return keys
    }

    static func parseMapping(_ text: String) -> [(key: String, value: YAMLValue)]? {
        guard let node = try? Yams.compose(yaml: text), case .mapping = node,
              case .mapping(let pairs) = convert(node) else { return nil }
        return pairs
    }

    private static func convert(_ node: Node) -> YAMLValue {
        switch node {
        case .scalar(let scalar):
            return .scalar(scalar.string, quoted: scalar.style == .singleQuoted || scalar.style == .doubleQuoted)
        case .sequence(let sequence):
            return .sequence(sequence.map(convert))
        case .mapping(let mapping):
            return .mapping(mapping.map { (key: $0.key.string ?? "", value: convert($0.value)) })
        default:
            return .scalar("", quoted: false)
        }
    }

    /// `line N: problem`, so the editor and the warning can point at the line.
    private static func describe(_ error: Error, in text: String) -> String {
        guard let yamlError = error as? YamlError else { return error.localizedDescription }
        switch yamlError {
        case .scanner(let context, let problem, let mark, _), .parser(let context, let problem, let mark, _),
             .composer(let context, let problem, let mark, _):
            // libyaml's problem mark is where it noticed the error. For something left unfinished
            // (a key with no `:`, an unclosed quote, `[` or `{`) that's the next line, and the context
            // mark is where the unfinished thing started. A block mapping context is just the
            // start of the mapping, so the problem mark is right there.
            var line = mark.line
            if let context, context.text.hasPrefix("while scanning") || context.text.contains("flow") {
                line = context.mark.line
            }
            return "line \(line): \(problem)"
        case .duplicatedKeysInMapping(let duplicates, _):
            // The context mark is the start of the mapping, so find the repeated key's line instead.
            let lines = text.components(separatedBy: "\n")
            let line = lines.indices.last { index in
                guard let (_, key, _) = TemplateRenderer.splitKeyValue(lines[index]) else { return false }
                return duplicates.contains(key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
            }
            let names = duplicates.joined(separator: ", ")
            return line.map { "line \($0 + 1): duplicate key \(names)" } ?? "duplicate key \(names)"
        default:
            return String(describing: yamlError).components(separatedBy: "\n").first ?? "invalid YAML"
        }
    }
}
