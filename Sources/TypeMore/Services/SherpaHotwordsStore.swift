import Foundation

final class SherpaHotwordsStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeBuiltinHotwords() throws -> URL? {
        let words = builtinHotwords()
        guard !words.isEmpty else { return nil }

        let directory = AppDirectories.applicationSupport(fileManager: fileManager, appending: "TypeMore/SherpaRuntime")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("hotwords.txt")
        try words.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func builtinHotwords() -> [String] {
        let codingWords = [
            "SwiftUI",
            "Xcode",
            "Cursor",
            "TypeScript",
            "JavaScript",
            "Python",
            "API",
            "JSON",
            "GitHub",
            "LLM"
        ]

        return Array(Set(codingWords.filter(isSupportedHotword))).sorted()
    }

    private func isSupportedHotword(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        guard word.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        return word.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar.value > 0x7F
        }
    }
}
