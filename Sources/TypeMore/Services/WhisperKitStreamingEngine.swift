import Foundation
import WhisperKit

actor WhisperKitStreamingEngine: StreamingSpeechEngine {
    private let modelName: String
    private let voiceActivityService: VoiceActivityService
    private var whisperKit: WhisperKit?
    private var audioBuffer: [Float] = []
    private var startedAt: Date?
    private var firstPartialAt: Date?
    private var lastPartialSampleCount = 0
    private var lastPartialText = ""
    private var lastPartialDate: Date?
    private var onPartial: (@Sendable (String) -> Void)?
    private var mode: DictationMode = .codingPrompt
    private var language: TranscriptionLanguage = .chinese

    init(
        modelName: String = "small",
        voiceActivityService: VoiceActivityService = SileroVoiceActivityService()
    ) {
        self.modelName = modelName
        self.voiceActivityService = voiceActivityService
    }

    func prepare(progress: @escaping @Sendable (SpeechModelState) -> Void) async throws -> SpeechModelState {
        if whisperKit != nil {
            return .ready("WhisperKit \(modelName) 已预热")
        }

        progress(.downloading(0.05))
        let config = WhisperKitConfig(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        whisperKit = try await WhisperKit(config)
        progress(.ready("WhisperKit \(modelName) 已预热"))
        return .ready("WhisperKit \(modelName) 已预热")
    }

    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        _ = try await prepare { _ in }
        self.mode = mode
        self.language = language
        self.onPartial = onPartial
        audioBuffer = []
        startedAt = Date()
        firstPartialAt = nil
        lastPartialSampleCount = 0
        lastPartialText = ""
        lastPartialDate = nil
        voiceActivityService.reset()
    }

    func acceptAudio(samples: [Float], sampleRate: Double) async {
        guard !samples.isEmpty else { return }
        audioBuffer.append(contentsOf: samples)
        let vad = voiceActivityService.accept(samples: samples, sampleRate: sampleRate)
        if vad.hasSpeech, lastPartialText.isEmpty {
            onPartial?("检测到语音...")
        }

        let now = Date()
        let enoughNewAudio = audioBuffer.count - lastPartialSampleCount >= Int(sampleRate)
        let enoughTime = lastPartialDate.map { now.timeIntervalSince($0) >= 0.8 } ?? true
        guard enoughNewAudio, enoughTime else { return }
        lastPartialSampleCount = audioBuffer.count
        lastPartialDate = now

        do {
            try await emitPartial(from: audioBuffer)
        } catch {
            // Partial decoding should never abort the active recording. Final decode reports real errors.
        }
    }

    func finish(recording: LiveRecordingSummary) async throws -> StreamingTranscriptionResult {
        guard !audioBuffer.isEmpty else {
            throw TypeMoreError.transcriptionUnavailable
        }

        let finalStart = Date()
        let text = try await transcribe(audioBuffer)
        let finalizationLatency = Date().timeIntervalSince(finalStart)
        let duration = recording.duration
        let realTimeFactor = duration > 0 ? finalizationLatency / duration : 0
        let firstPartialLatency = firstPartialAt.flatMap { startedAt?.distance(to: $0) }

        resetSession(keepingModel: true)
        return StreamingTranscriptionResult(
            text: text,
            backend: .whisperKitStreaming,
            duration: duration,
            realTimeFactor: realTimeFactor,
            firstPartialLatency: firstPartialLatency,
            finalizationLatency: finalizationLatency,
            debugAudioURL: recording.fileURL
        )
    }

    func cancel() async {
        resetSession(keepingModel: true)
    }

    private func emitPartial(from samples: [Float]) async throws {
        let text = try await transcribe(samples)
        guard !text.isEmpty, text != lastPartialText else { return }
        if firstPartialAt == nil {
            firstPartialAt = Date()
        }
        lastPartialText = text
        onPartial?(text)
    }

    private func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisperKit else {
            throw TypeMoreError.recognitionBackendUnavailable("WhisperKit 模型尚未加载。")
        }
        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperLanguageCode,
            temperatureFallbackCount: 0,
            usePrefillPrompt: !language.shouldDetectLanguage,
            detectLanguage: language.shouldDetectLanguage,
            skipSpecialTokens: true
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TypeMoreError.transcriptionUnavailable
        }
        return text
    }

    private func resetSession(keepingModel: Bool) {
        audioBuffer = []
        startedAt = nil
        firstPartialAt = nil
        lastPartialSampleCount = 0
        lastPartialText = ""
        lastPartialDate = nil
        onPartial = nil
        voiceActivityService.reset()
        if !keepingModel {
            whisperKit = nil
        }
    }
}
