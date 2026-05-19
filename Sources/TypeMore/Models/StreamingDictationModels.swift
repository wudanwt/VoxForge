import Foundation

enum SpeechModelState: Equatable, Sendable {
    case unchecked
    case missingRuntime
    case missingModel
    case downloading(Double)
    case ready(String)
    case failed(String)

    var title: String {
        switch self {
        case .unchecked:
            "尚未检查"
        case .missingRuntime:
            "缺少识别运行库"
        case .missingModel:
            "需要下载识别模型"
        case .downloading(let progress):
            "正在下载模型 \(Int(progress * 100))%"
        case .ready(let version):
            version.isEmpty ? "识别模型已就绪" : "识别模型已就绪（\(version)）"
        case .failed(let message):
            "模型不可用：\(message)"
        }
    }
}

struct LiveRecordingSummary: Sendable {
    var fileURL: URL?
    var duration: TimeInterval
    var sampleRate: Double
    var samplesRecorded: Int
}

struct StreamingTranscriptionResult: Sendable {
    var text: String
    var backend: RecognitionBackend
    var duration: TimeInterval
    var realTimeFactor: Double
    var firstPartialLatency: TimeInterval?
    var finalizationLatency: TimeInterval
    var debugAudioURL: URL?
}

struct SherpaModelPaths: Sendable, Equatable {
    var directory: URL
    var encoder: URL
    var decoder: URL
    var tokens: URL
}

struct VoiceActivityConfiguration: Equatable, Sendable {
    var preBufferDuration: TimeInterval = 0.3
    var silenceEndDuration: TimeInterval = 0.7
    var minimumSpeechDuration: TimeInterval = 0.5
    var maximumSegmentDuration: TimeInterval = 12
    var activationThreshold: Float = 0.015
}

struct VoiceActivityDecision: Equatable, Sendable {
    var hasSpeech: Bool
    var shouldFinalizeSegment: Bool
    var speechDuration: TimeInterval
    var trailingSilenceDuration: TimeInterval
}
