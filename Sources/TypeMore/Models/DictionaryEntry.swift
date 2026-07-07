import Foundation

struct DictionaryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var term: String
    var aliases: [String]
    var note: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        term: String,
        aliases: [String] = [],
        note: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.note = note
        self.isEnabled = isEnabled
    }

    init(spoken: String, replacement: String) {
        let alias = spoken == replacement ? [] : [spoken]
        self.init(term: replacement, aliases: alias)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case term
        case aliases
        case note
        case isEnabled
        case spoken
        case replacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        if let term = try container.decodeIfPresent(String.self, forKey: .term) {
            self.term = term
            aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
            note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
            return
        }

        let spoken = try container.decodeIfPresent(String.self, forKey: .spoken) ?? ""
        let replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? spoken
        term = replacement
        aliases = spoken == replacement ? [] : [spoken]
        note = ""
        isEnabled = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(term, forKey: .term)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(note, forKey: .note)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    static let defaults: [DictionaryEntry] = [
        DictionaryEntry(term: "SwiftUI", aliases: ["swift ui"], note: "Apple UI 框架"),
        DictionaryEntry(term: "Xcode", aliases: ["x code"], note: "Apple 开发工具"),
        DictionaryEntry(term: "Cursor", note: "AI 代码编辑器"),
        DictionaryEntry(term: "Claude Code", aliases: ["claude code"], note: "AI 编程工具"),
        DictionaryEntry(term: "VoxForge 声铸", aliases: ["type more", "vox forge", "声铸"], note: "当前应用名称")
    ]
}
