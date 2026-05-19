import Foundation

@available(*, deprecated, message: "Use WhisperKitTranscriptionEngine for real dictation.")
final class LocalPlaceholderTranscriptionEngine: TranscriptionEngine {
    func transcribe(audio: RecordedAudio, mode: DictationMode, language: TranscriptionLanguage) async throws -> String {
        try await Task.sleep(nanoseconds: 350_000_000)
        switch mode {
        case .literal:
            return "echo \"hello from VoxForge\""
        case .general:
            return "呃，请帮我把这段想法整理成更清晰的一段话。"
        case .codingPrompt:
            return "呃，帮我重构这个 Swift UI 视图，保持现有行为，然后补充单元测试。"
        }
    }
}
