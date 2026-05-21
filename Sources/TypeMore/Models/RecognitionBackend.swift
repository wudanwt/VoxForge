import Foundation

enum RecognitionBackend: String, CaseIterable, Codable, Identifiable, Sendable {
    case sherpaParaformer
    case whisperKitStreaming
    case whisperKit
    case appleDictation

    var id: String { rawValue }

    static var isAppleDictationSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    static var selectableCases: [RecognitionBackend] {
        selectableCases(isAppleDictationSupported: isAppleDictationSupported)
    }

    static func selectableCases(isAppleDictationSupported: Bool) -> [RecognitionBackend] {
        var cases: [RecognitionBackend] = [.sherpaParaformer, .whisperKitStreaming, .whisperKit]
        if isAppleDictationSupported {
            cases.append(.appleDictation)
        }
        return cases
    }

    var title: String {
        switch self {
        case .sherpaParaformer:
            "中文极速本地"
        case .whisperKitStreaming:
            "WhisperKit 流式"
        case .whisperKit:
            "WhisperKit 兼容"
        case .appleDictation:
            "Apple 原生听写"
        }
    }

    var description: String {
        switch self {
        case .sherpaParaformer:
            "sherpa-onnx Streaming Paraformer，中文和中英混说优先。"
        case .whisperKitStreaming:
            "WhisperKit 常驻预热 + 内存流式识别 + VAD 分段，适合高精度本地听写。"
        case .whisperKit:
            "录完后使用 WhisperKit 整段转写，作为兼容兜底。"
        case .appleDictation:
            "macOS 26+ SpeechAnalyzer / DictationTranscriber，系统原生听写，实验可选。"
        }
    }

    var isStreaming: Bool {
        switch self {
        case .sherpaParaformer, .whisperKitStreaming, .appleDictation:
            true
        case .whisperKit:
            false
        }
    }
}
