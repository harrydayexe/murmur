import Foundation
import FoundationModels

/// Generates only the needed metadata fields with a runtime schema (SPEC §6.5).
struct MetadataGenerator: MetadataGenerating {
    static let instructions = """
        You write metadata for a spoken voice note. Use only what the speaker actually said. \
        Never add facts, opinions or details that aren't in the transcript.
        """

    func generate(_ request: MetadataRequest) async throws -> GeneratedMetadata {
        guard !request.fields.isEmpty else { return GeneratedMetadata() }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        try ModelStatus.requireAvailable(model)

        let schema = try Self.schema(for: request)
        var input = request.transcript
        if try await model.tokenCount(for: input) > model.contextSize - 800 {
            input = try await condense(input, model: model)
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: Prompt("Voice note transcript:\n\n\(input)"),
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let content = response.content

        var metadata = GeneratedMetadata()
        let fields = request.fields
        if fields.contains(.title) { metadata.title = (try? content.value(String.self, forProperty: "title")) ?? "" }
        if fields.contains(.summary) { metadata.summary = (try? content.value(String.self, forProperty: "summary")) ?? "" }
        if fields.contains(.keyPoints) { metadata.keyPoints = (try? content.value([String].self, forProperty: "keyPoints")) ?? [] }
        if fields.contains(.type) {
            let type = (try? content.value(String.self, forProperty: "type")) ?? ""
            metadata.type = request.noteTypes.contains(type) ? type : ""
        }
        if fields.contains(.tags) { metadata.tags = (try? content.value([String].self, forProperty: "tags")) ?? [] }
        return metadata
    }

    static func schema(for request: MetadataRequest) throws -> GenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        let string = DynamicGenerationSchema(type: String.self)

        if request.fields.contains(.title) {
            properties.append(.init(name: "title", description: "A title of at most 8 words that reuses the speaker's phrasing", schema: string))
        }
        if request.fields.contains(.summary) {
            properties.append(.init(name: "summary", description: "One or two plain sentences; nothing that wasn't stated", schema: string))
        }
        if request.fields.contains(.keyPoints) {
            properties.append(.init(
                name: "keyPoints",
                description: "Up to five key points, each something the speaker said",
                schema: DynamicGenerationSchema(arrayOf: string, minimumElements: 0, maximumElements: 5)
            ))
        }
        if request.fields.contains(.type), !request.noteTypes.isEmpty {
            properties.append(.init(
                name: "type",
                description: "The kind of note",
                schema: DynamicGenerationSchema(name: "NoteType", anyOf: request.noteTypes)
            ))
        }
        if request.fields.contains(.tags) {
            let allowed = request.tags.allowed.filter { !$0.isEmpty }
            let item: DynamicGenerationSchema? = switch request.tags.mode {
            case .free: string
            case .allowedOnly: allowed.isEmpty ? nil : DynamicGenerationSchema(name: "Tag", anyOf: allowed)
            }
            if let item {
                properties.append(.init(
                    name: "tags",
                    description: "Short topic tags for the note",
                    schema: DynamicGenerationSchema(arrayOf: item, minimumElements: 0, maximumElements: request.tags.maxCount)
                ))
            }
        }

        let root = DynamicGenerationSchema(name: "NoteMetadata", properties: properties)
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Map step for long transcripts: one sentence per chunk.
    private func condense(_ text: String, model: SystemLanguageModel) async throws -> String {
        let budget = max(64, min(1200, (model.contextSize - 400) / 2))
        let chunks = try await Chunker.chunks(of: text, budget: budget) { try await model.tokenCount(for: $0) }
        var sentences: [String] = []
        for chunk in chunks {
            let session = LanguageModelSession(
                model: model,
                instructions: "Summarise this part of a voice note in one plain sentence. Use only what is stated."
            )
            let response = try await session.respond(to: Prompt(chunk), options: GenerationOptions(samplingMode: .greedy))
            sentences.append(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return sentences.joined(separator: " ")
    }
}
