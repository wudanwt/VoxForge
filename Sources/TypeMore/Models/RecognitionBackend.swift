import Foundation

enum RecognitionBackend: String, CaseIterable, Codable, Identifiable, Sendable {
    case sherpaParaformer
    case whisperKitStreaming
    case whisperKit
    case appleDictation

    var id: String { rawValue }

    static var selectableCases: [RecognitionBackend] {
        [.sherpaParaformer, .whisperKitStreaming, .whisperKit]
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
            "预留 macOS 26+ SpeechAnalyzer / DictationTranscriber 后端，当前版本会明确提示不可用。"
        }
    }

    var isStreaming: Bool {
        switch self {
        case .sherpaParaformer, .whisperKitStreaming:
            true
        case .whisperKit, .appleDictation:
            false
        }
    }
}
