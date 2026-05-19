import Foundation

final class CodingPromptPostProcessor: PostProcessingService {
    private let fillerPatterns = [
        "呃", "嗯", "那个", "就是", "然后呢", "的话", "um", "uh", "you know"
    ]

    func process(_ text: String, mode: DictationMode, profile: AppProfile, dictionary: [DictionaryEntry]) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for entry in dictionary {
            output = output.replacingOccurrences(
                of: entry.spoken,
                with: entry.replacement,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }

        guard mode != .literal else {
            return output
        }

        for filler in fillerPatterns {
            output = output.replacingOccurrences(of: filler, with: "")
        }

        output = collapseWhitespace(output)

        if mode == .codingPrompt {
            output = output
                .replacingOccurrences(of: "Swift UI", with: "SwiftUI")
                .replacingOccurrences(of: "单元 测试", with: "单元测试")
                .replacingOccurrences(of: "vibe Codinging", with: "vibe coding")
        }

        return trimLoosePunctuation(output)
    }

    private func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func trimLoosePunctuation(_ text: String) -> String {
        let punctuation = CharacterSet(charactersIn: "，,。.!！？?、；;：: ")
        return text.trimmingCharacters(in: punctuation.union(.whitespacesAndNewlines))
    }
}
