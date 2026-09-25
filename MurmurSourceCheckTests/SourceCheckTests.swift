import Foundation
import Testing

/// Enforces SPEC §1: no networking APIs and no non-Apple or cloud models anywhere in the app.
struct SourceCheckTests {
    static let repoRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static let forbidden = [
        "URLSession",
        "import Network",
        "NWConnection",
        "PrivateCloudComputeLanguageModel",
        "OpenAI",
        "Anthropic",
        "Whisper",
        "Gemini",
    ]

    func appSources() throws -> [URL] {
        let root = Self.repoRoot.appending(path: "Murmur")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test func noNetworkingOrThirdPartyModels() throws {
        let sources = try appSources()
        #expect(!sources.isEmpty)
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for term in Self.forbidden {
                #expect(!text.contains(term), "\(file.lastPathComponent) mentions \(term)")
            }
        }
    }

    @Test func noNetworkEntitlement() throws {
        let yml = try String(contentsOf: Self.repoRoot.appending(path: "project.yml"), encoding: .utf8)
        #expect(!yml.contains("network.client"))
        #expect(!yml.contains("network.server"))
    }
}
