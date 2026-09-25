import Foundation

struct PolishResult: Equatable, Sendable {
    var text: String
    /// True if any chunk fell back to the raw text.
    var fellBack: Bool
}

/// Light tidying of a transcript (SPEC §6.4).
protocol TextPolishing: Sendable {
    func polish(
        _ text: String,
        glossary: [String],
        progress: @escaping @Sendable (_ chunk: Int, _ of: Int) async -> Void
    ) async throws -> PolishResult
}

struct MetadataRequest: Equatable, Sendable {
    var transcript: String
    var fields: Set<MetadataField>
    var noteTypes: [String]
    var tags: TagSettings
}

struct GeneratedMetadata: Equatable, Sendable {
    var title = ""
    var summary = ""
    var keyPoints: [String] = []
    var type = ""
    var tags: [String] = []
}

/// Generates only the requested metadata fields (SPEC §6.5).
protocol MetadataGenerating: Sendable {
    func generate(_ request: MetadataRequest) async throws -> GeneratedMetadata
}

enum AIError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Apple Intelligence is unavailable (\(reason))."
        }
    }
}
