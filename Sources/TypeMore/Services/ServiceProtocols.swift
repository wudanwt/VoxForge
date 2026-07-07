import Foundation

struct RecordedAudio: Sendable {
    var fileURL: URL
    var duration: TimeInterval
    var sampleRate: Double
    var samplesRecorded: Int
}

protocol AudioRecordingService {
    func startRecording() throws
    func stopRecording() throws -> RecordedAudio
}

protocol LiveAudioRecordingService {
    func startStreaming(
        keepDebugFile: Bool,
        onSamples: @escaping @Sendable ([Float], Double) -> Void,
        onStreamInterrupted: @escaping @Sendable (Error) -> Void
    ) throws
    func stopStreaming() throws -> LiveRecordingSummary
}

protocol TranscriptionEngine {
    func transcribe(audio: RecordedAudio, mode: DictationMode, language: TranscriptionLanguage) async throws -> String
}

protocol StreamingTranscriptionEngine {
    func prepare(
        dictionary: [DictionaryEntry],
        progress: @escaping @Sendable (SpeechModelState) -> Void
    ) async throws -> SpeechModelState
    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws
    func acceptAudio(samples: [Float], sampleRate: Double) async
    func finish(recording: LiveRecordingSummary) async throws -> StreamingTranscriptionResult
    func cancel() async
}

typealias StreamingSpeechEngine = StreamingTranscriptionEngine

protocol VoiceActivityService: Sendable {
    var configuration: VoiceActivityConfiguration { get }
    func reset()
    func accept(samples: [Float], sampleRate: Double) -> VoiceActivityDecision
}

struct LLMOptimizationConfiguration: Codable, Hashable {
    var isEnabled: Bool
    var baseURL: String
    var apiKey: String
    var model: String
    var styleInstruction: String
    var customPrompt: String
    var dictionaryContext: String

    static let disabled = LLMOptimizationConfiguration(
        isEnabled: false,
        baseURL: "https://api.openai.com/v1",
        apiKey: "",
        model: "gpt-4.1-mini",
        styleInstruction: "直接可发送的编程提示词",
        customPrompt: "",
        dictionaryContext: ""
    )
}

protocol LLMOptimizationService {
    func optimize(
        text: String,
        rawText: String,
        mode: DictationMode,
        profile: AppProfile,
        configuration: LLMOptimizationConfiguration
    ) async throws -> String
}

protocol PostProcessingService {
    func process(_ text: String, mode: DictationMode, profile: AppProfile, dictionary: [DictionaryEntry]) -> String
}

protocol TextInsertionService {
    func insert(_ text: String, targetBundleIdentifier: String?) async throws
    func sendReturn(targetBundleIdentifier: String?) async throws
}

protocol PermissionCoordinator {
    var hasAccessibilityPermission: Bool { get }
    func ensureMicrophonePermission() async -> Bool
    func openAccessibilityPrompt()
}

protocol HotkeyCoordinator {
    @MainActor
    func registerHotkeys(
        dictationHotkey: HotkeyDefinition,
        returnHotkey: HotkeyDefinition,
        cancelHotkey: HotkeyDefinition,
        onToggleDictation: @escaping () -> Void,
        onSendReturn: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> [HotkeyRegistrationResult]
}
