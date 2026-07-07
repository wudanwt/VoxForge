import Foundation

enum TypeMoreError: LocalizedError {
    case recordingNotActive
    case recordingFileMissing
    case transcriptionUnavailable
    case llmAPIKeyMissing
    case audioConversionUnavailable
    case sherpaRuntimeUnavailable(String)
    case sherpaModelMissing
    case sherpaModelExtractionFailed
    case modelDownloadFailed(String)
    case recognitionBackendUnavailable(String)
    case operationTimedOut(String)
    case diagnosticExportFailed(String)
    case targetActivationFailed(String)
    case audioInputConfigurationChanged

    var errorDescription: String? {
        switch self {
        case .recordingNotActive:
            "Recording is not active."
        case .recordingFileMissing:
            "Recording file is missing."
        case .transcriptionUnavailable:
            "没有识别到语音文本。请确认麦克风输入正常，并至少说 1 秒以上。"
        case .llmAPIKeyMissing:
            "LLM API key is missing."
        case .audioConversionUnavailable:
            "Audio conversion is unavailable."
        case .sherpaRuntimeUnavailable(let message):
            message
        case .sherpaModelMissing:
            "Sherpa Paraformer model files are missing."
        case .sherpaModelExtractionFailed:
            "Failed to extract Sherpa Paraformer model archive."
        case .modelDownloadFailed(let message):
            message
        case .recognitionBackendUnavailable(let message):
            message
        case .operationTimedOut(let message):
            message
        case .diagnosticExportFailed(let message):
            "导出诊断包失败：\(message)"
        case .targetActivationFailed(let appName):
            "目标应用未能激活：\(appName)"
        case .audioInputConfigurationChanged:
            "音频输入设备已变化，听写已停止，请重试。"
        }
    }
}

extension TypeMoreError {
    var isOperationTimeout: Bool {
        if case .operationTimedOut = self {
            return true
        }
        return false
    }
}
