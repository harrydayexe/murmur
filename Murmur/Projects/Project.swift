import Foundation

struct Project: Codable, Identifiable, Equatable, Sendable {
    struct FrontMatter: Codable, Equatable, Sendable {
        var mode = FrontMatterMode.inherit
        var template = ""
        var timelineTemplate = ""

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decodeIfPresent(FrontMatterMode.self, forKey: .mode) ?? .inherit
            template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
            timelineTemplate = try container.decodeIfPresent(String.self, forKey: .timelineTemplate) ?? ""
        }
    }

    var id = UUID()
    var name: String
    /// Security-scoped bookmark. Nil until the user grants access to a folder.
    var folderBookmark: Data?
    var folderPathHint: String
    var style = NoteStyleKind.standard
    var vaultRootPathHint: String?
    var frontMatter = FrontMatter()
    var glossary: [String] = []
    var defaultNoteType: String?
    var archived = false

    init(id: UUID = UUID(), name: String, folderBookmark: Data? = nil, folderPathHint: String = "",
         style: NoteStyleKind = .standard) {
        self.id = id
        self.name = name
        self.folderBookmark = folderBookmark
        self.folderPathHint = folderPathHint
        self.style = style
    }

    // Tolerant decoding: a hand-edited file can leave out any key but `name`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        folderBookmark = try container.decodeIfPresent(Data.self, forKey: .folderBookmark)
        folderPathHint = try container.decodeIfPresent(String.self, forKey: .folderPathHint) ?? ""
        style = try container.decodeIfPresent(NoteStyleKind.self, forKey: .style) ?? .standard
        vaultRootPathHint = try container.decodeIfPresent(String.self, forKey: .vaultRootPathHint)
        frontMatter = try container.decodeIfPresent(FrontMatter.self, forKey: .frontMatter) ?? FrontMatter()
        glossary = try container.decodeIfPresent([String].self, forKey: .glossary) ?? []
        defaultNoteType = try container.decodeIfPresent(String.self, forKey: .defaultNoteType)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}
