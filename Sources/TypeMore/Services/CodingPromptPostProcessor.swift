import Foundation

final class CodingPromptPostProcessor: PostProcessingService {
    func process(_ text: String, mode: DictationMode, profile: AppProfile, dictionary _: [DictionaryEntry]) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard mode != .literal else {
            return output
        }

        output = removeSafeFillers(output)
        output = collapseWhitespace(output)

        if mode == .codingPrompt {
            output = output
                .replacingOccurrences(of: "Swift UI", with: "SwiftUI")
                .replacingOccurrences(of: "单元 测试", with: "单元测试")
        }

        return trimLoosePunctuation(output)
    }

    private func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }

    private func removeSafeFillers(_ text: String) -> String {
        var output = text
        let patterns = [
            #"(^|[\n，,。.!！？?、；;：:\s])(呃|嗯|那个|然后呢)(?=[\s，,。.!！？?、；;：:]|$)"#,
            #"(^|[\n，,。.!！？?、；;：:\s])就是说(?=\S)"#,
            #"(^|[\n，,。.!！？?、；;：:\s])(um|uh|you know)(?=[\s，,。.!！？?、；;：:]|$)"#
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return output
    }

    private func trimLoosePunctuation(_ text: String) -> String {
        let punctuation = CharacterSet(charactersIn: "，,。.!！？?、；;：: ")
        return text.trimmingCharacters(in: punctuation.union(.whitespacesAndNewlines))
    }
}
