import Foundation

final class OpenAICompatibleOptimizationService: LLMOptimizationService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func optimize(
        text: String,
        rawText: String,
        mode: DictationMode,
        profile: AppProfile,
        configuration: LLMOptimizationConfiguration
    ) async throws -> String {
        guard configuration.isEnabled else { return text }
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw TypeMoreError.llmAPIKeyMissing }

        let endpoint = try chatCompletionsURL(from: configuration.baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let payload = ChatCompletionsRequest(
            model: configuration.model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: systemPrompt(
                        style: configuration.styleInstruction,
                        customPrompt: configuration.customPrompt,
                        rawText: rawText,
                        cleanedText: text,
                        mode: mode,
                        profile: profile
                    )
                ),
                ChatMessage(role: "user", content: userPrompt(rawText: rawText, cleanedText: text))
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw LLMOptimizationError.badStatus(httpResponse.statusCode)
        }

        let optimized = try Self.extractOptimizedText(from: data)
        return optimized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractOptimizedText(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw LLMOptimizationError.emptyResponse
        }
        return text
    }

    private func chatCompletionsURL(from baseURLString: String) throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil else {
            throw LLMOptimizationError.invalidBaseURL
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") {
            return components.url!
        }
        components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else { throw LLMOptimizationError.invalidBaseURL }
        return url
    }

    private func systemPrompt(
        style: String,
        customPrompt: String,
        rawText: String,
        cleanedText: String,
        mode: DictationMode,
        profile: AppProfile
    ) -> String {
        let template = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            return defaultSystemPrompt(style: style, mode: mode, profile: profile)
        }
        return renderPromptTemplate(
            template,
            style: style,
            rawText: rawText,
            cleanedText: cleanedText,
            mode: mode,
            profile: profile
        )
    }

    private func defaultSystemPrompt(style: String, mode: DictationMode, profile: AppProfile) -> String {
        renderPromptTemplate(
            Self.defaultPromptTemplate,
            style: style,
            rawText: "",
            cleanedText: "",
            mode: mode,
            profile: profile
        )
    }

    private func userPrompt(rawText: String, cleanedText: String) -> String {
        "原始转写：\n\(rawText)\n\n本地清理后：\n\(cleanedText)\n\n请只输出最终要粘贴的文本，不要解释。"
    }

    private func renderPromptTemplate(
        _ template: String,
        style: String,
        rawText: String,
        cleanedText: String,
        mode: DictationMode,
        profile: AppProfile
    ) -> String {
        template
            .replacingOccurrences(of: "{rawTranscript}", with: rawText)
            .replacingOccurrences(of: "{cleanedText}", with: cleanedText)
            .replacingOccurrences(of: "{mode}", with: mode.title)
            .replacingOccurrences(of: "{app}", with: profile.displayName)
            .replacingOccurrences(of: "{style}", with: style)
    }

    static let defaultPromptTemplate = """
    你是 VoxForge 声铸的语音输入优化器。你的任务是把语音转写结果整理成用户可以直接发送或粘贴的文本。
    输出要求：
    - 只输出最终文本，不要解释。
    - 保留代码符号、英文标识符、文件名、命令行、API 名称。
    - 删除口头禅、重复改口和无意义停顿。
    - 当前模式：{mode}。
    - 目标应用：{app}。
    - 优化风格：{style}。
    """
}

enum LLMOptimizationError: LocalizedError {
    case invalidBaseURL
    case badStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "大模型 Base URL 无效。"
        case .badStatus(let statusCode):
            "大模型请求失败：HTTP \(statusCode)。"
        case .emptyResponse:
            "大模型没有返回可用文本。"
        }
    }
}

private struct ChatCompletionsRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionsResponse: Codable {
    var choices: [Choice]

    struct Choice: Codable {
        var message: ChatMessage
    }
}
