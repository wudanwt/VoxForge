import Foundation

enum DictationMode: String, CaseIterable, Codable, Identifiable {
    case literal
    case general
    case codingPrompt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .literal: "原文模式"
        case .general: "通用整理"
        case .codingPrompt: "编程提示词"
        }
    }

    var description: String {
        switch self {
        case .literal:
            "尽量保留原话，只做最少清理。"
        case .general:
            "清理口头禅，把语音整理成自然文本。"
        case .codingPrompt:
            "保留代码术语，把中英混说整理成清晰的编程提示词。"
        }
    }
}
