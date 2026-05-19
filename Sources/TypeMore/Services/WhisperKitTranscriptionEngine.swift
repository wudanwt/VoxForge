import Foundation
import WhisperKit

actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private let modelName: String?

    init(modelName: String? = nil) {
        self.modelName = modelName
    }

    func transcribe(audio: RecordedAudio, mode: DictationMode, language: TranscriptionLanguage) async throws -> String {
        let pipe = try await loadWhisperKit()
        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperLanguageCode,
            temperatureFallbackCount: 0,
            usePrefillPrompt: !language.shouldDetectLanguage,
            detectLanguage: language.shouldDetectLanguage,
            skipSpecialTokens: true
        )
        let results = try await pipe.transcribe(audioPath: audio.fileURL.path, decodeOptions: options)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TypeMoreError.transcriptionUnavailable
        }
        return text
    }

    private func loadWhisperKit() async throws -> WhisperKit {
        if let whisperKit {
            return whisperKit
        }

        let created: WhisperKit
        if let modelName, !modelName.isEmpty {
            created = try await WhisperKit(WhisperKitConfig(model: modelName))
        } else {
            created = try await WhisperKit()
        }
        whisperKit = created
        return created
    }
}
