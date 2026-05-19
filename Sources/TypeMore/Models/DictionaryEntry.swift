import Foundation

struct DictionaryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var spoken: String
    var replacement: String

    static let defaults: [DictionaryEntry] = [
        DictionaryEntry(spoken: "vibe coding", replacement: "vibe coding"),
        DictionaryEntry(spoken: "swift ui", replacement: "SwiftUI"),
        DictionaryEntry(spoken: "x code", replacement: "Xcode"),
        DictionaryEntry(spoken: "cursor", replacement: "Cursor"),
        DictionaryEntry(spoken: "claude code", replacement: "Claude Code"),
        DictionaryEntry(spoken: "type more", replacement: "VoxForge 声铸"),
        DictionaryEntry(spoken: "vox forge", replacement: "VoxForge 声铸"),
        DictionaryEntry(spoken: "声铸", replacement: "VoxForge 声铸")
    ]
}
