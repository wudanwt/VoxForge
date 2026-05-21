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
                        profile: profile,
                        dictionaryContext: configuration.dictionaryContext
                    )
                ),
                ChatMessage(role: "user", content: userPrompt(
                    rawText: rawText,
                    cleanedText: text,
                    dictionaryContext: configuration.dictionaryContext
                ))
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
        profile: AppProfile,
        dictionaryContext: String
    ) -> String {
        let template = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            return defaultSystemPrompt(style: style, mode: mode, profile: profile, dictionaryContext: dictionaryContext)
        }
        return renderPromptTemplate(
            template,
            style: style,
            rawText: rawText,
            cleanedText: cleanedText,
            mode: mode,
            profile: profile,
            dictionaryContext: dictionaryContext
        )
    }

    private func defaultSystemPrompt(
        style: String,
        mode: DictationMode,
        profile: AppProfile,
        dictionaryContext: String
    ) -> String {
        renderPromptTemplate(
            Self.defaultPromptTemplate(for: mode),
            style: style,
            rawText: "",
            cleanedText: "",
            mode: mode,
            profile: profile,
            dictionaryContext: dictionaryContext
        )
    }

    private func userPrompt(rawText: String, cleanedText: String, dictionaryContext: String) -> String {
        let dictionarySection = dictionaryContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "个人词典：无"
            : "个人词典：\n\(dictionaryContext)"
        return "\(dictionarySection)\n\n原始转写：\n\(rawText)\n\n本地清理后：\n\(cleanedText)\n\n请只输出最终要粘贴的文本，不要解释。"
    }

    private func renderPromptTemplate(
        _ template: String,
        style: String,
        rawText: String,
        cleanedText: String,
        mode: DictationMode,
        profile: AppProfile,
        dictionaryContext: String
    ) -> String {
        template
            .replacingOccurrences(of: "{rawTranscript}", with: rawText)
            .replacingOccurrences(of: "{cleanedText}", with: cleanedText)
            .replacingOccurrences(of: "{mode}", with: mode.title)
            .replacingOccurrences(of: "{app}", with: profile.displayName)
            .replacingOccurrences(of: "{style}", with: style)
            .replacingOccurrences(of: "{dictionary}", with: dictionaryContext)
    }

    static func dictionaryContext(from entries: [DictionaryEntry]) -> String {
        let lines = entries
            .filter(\.isEnabled)
            .compactMap { entry -> String? in
                let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty else { return nil }
                let aliases = entry.aliases
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
                var parts = ["标准词条：\(term)"]
                if !aliases.isEmpty {
                    parts.append("常见误听：\(aliases.joined(separator: "、"))")
                }
                if !note.isEmpty {
                    parts.append("说明：\(note)")
                }
                return "- " + parts.joined(separator: "；")
            }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n")
    }

    static let defaultPromptTemplate = defaultPromptTemplate(for: .codingPrompt)

    static func defaultPromptTemplate(for mode: DictationMode) -> String {
        switch mode {
        case .literal:
            """
            你是 VoxForge 声铸的原文模式文本修正器。你的任务是尽量保留用户原话，只做最低限度的可读性处理。

            输出要求：
            - 只输出最终要粘贴/发送的文本，不要解释。
            - 尽量保留用户原始措辞、语气、顺序和中英混排。
            - 只删除明显口头禅、重复音、无意义停顿。
            - 自动补充必要标点，把明显过长的句子拆成短句。
            - 参考个人词典修正人名、项目名、产品名和专有名词；只有上下文、读音或常见误听匹配时才使用词典，不要机械替换。
            - 不总结、不扩写、不改写成正式文风。
            - 保留技术关键词、英文标识符、文件名、命令、路径、错误信息、API 名称。
            - 个人词典：
            {dictionary}
            - 当前模式：{mode}。
            - 目标应用：{app}。
            - 优化风格：{style}。
            """
        case .general:
            """
            你是 VoxForge 声铸的通用语音文本整理器。你的任务是把语音转写整理成自然、清晰、适合直接发送的文本。

            输出要求：
            - 只输出最终要粘贴/发送的文本，不要解释。
            - 删除口头禅、重复、犹豫、改口和无意义停顿。
            - 自动补充中文/英文标点，优先使用短句。
            - 保留用户真实意图，不新增事实，不编造细节。
            - 参考个人词典修正人名、项目名、产品名和专有名词；只有上下文、读音或常见误听匹配时才使用词典，不要机械替换。
            - 内容较短时只做轻量润色；内容较长时分段或列点。
            - 保留必要的技术词、英文、数字、文件名、命令和专有名词。
            - 个人词典：
            {dictionary}
            - 当前模式：{mode}。
            - 目标应用：{app}。
            - 优化风格：{style}。
            """
        case .codingPrompt:
            """
            你是 VoxForge 声铸的编程语音输入优化器。你的任务是把用户的语音转写内容整理成适合 AI 编程助手、代码编辑器、终端或聊天窗口直接发送的文本。

            核心目标：
            1. 总结与结构化：把零散口语整理成清晰的需求、问题、步骤或待办。
            2. 文本润色：删除口头禅、重复、犹豫、改口和无意义停顿，让表达更准确。
            3. 标点与短句：自动补充中文/英文标点；把过长句拆成短句；让文本更容易被 AI 编程工具理解。

            重要原则：
            - 只输出最终要粘贴/发送的文本，不要解释你的修改过程。
            - 保留用户真实意图，不新增事实，不编造技术细节。
            - 不要求输出严格符合某种编程语言语法；重点是让需求、问题和上下文清楚。
            - 参考个人词典修正人名、项目名、产品名和专有名词；只有上下文、读音或常见误听匹配时才使用词典，不要机械替换，不要强行把普通词替换成词典项。
            - 保留技术关键词、英文标识符、文件名、函数名、类名、命令、路径、错误信息、API 名称。
            - 如果用户在描述 bug，整理成“现象 / 期望 / 请执行”的结构。
            - 如果用户在提需求，整理成“目标 / 关键要求 / 验收标准”的结构。
            - 如果用户在下达短命令，只做轻量润色，不要扩写。
            - 如果内容很短，保持短，不要强行结构化。
            - 如果用户说的是中文夹英文，保持自然中英混排。
            - 如果用户明确说“原样”“不要改”“照着写”，尽量少改，只补必要标点。
            - 个人词典：
            {dictionary}
            - 当前模式：{mode}。
            - 目标应用：{app}。
            - 优化风格：{style}。
            """
        }
    }
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
