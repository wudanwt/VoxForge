import Foundation

enum DictationSessionState: String, Codable {
    case idle
    case recording
    case processing
    case optimizing
    case inserting
    case readyToSubmit
    case failed

    var hudTitle: String {
        switch self {
        case .idle: "准备就绪"
        case .recording: "正在听写"
        case .processing: "正在转写"
        case .optimizing: "正在优化"
        case .inserting: "正在输入"
        case .readyToSubmit: "等待发送"
        case .failed: "发生错误"
        }
    }

    var hudSymbolName: String {
        switch self {
        case .idle: "mic"
        case .recording: "record.circle"
        case .processing: "waveform"
        case .optimizing: "sparkles"
        case .inserting: "keyboard"
        case .readyToSubmit: "return"
        case .failed: "exclamationmark.triangle"
        }
    }
}
