import Foundation
import XCTest
@testable import TypeMore

@MainActor
final class AppModelStateMachineTests: XCTestCase {
    func testStreamingFlowReachesReadyToSubmitAndSendReturnReturnsIdle() async throws {
        let textInsertion = RecordingTextInsertionService()
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: StateMachineStreamingEngine(finalText: "最终文本"),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            llmOptimizationService: PassthroughLLMService(),
            textInsertionService: textInsertion,
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: StateMachineHotkeyCoordinator()
        )

        await appModel.startDictation()
        XCTAssertEqual(appModel.sessionState, .recording)

        await appModel.finishDictation()
        XCTAssertEqual(appModel.sessionState, .readyToSubmit)
        XCTAssertEqual(appModel.lastTranscript, "最终文本")
        let insertedTexts = await textInsertion.insertedTextsSnapshot()
        XCTAssertEqual(insertedTexts, ["最终文本"])

        appModel.sendReturn()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appModel.sessionState, .idle)
        let returnCount = await textInsertion.returnCountSnapshot()
        XCTAssertEqual(returnCount, 1)
    }

    func testLLMFailureFallsBackToLocalResultAndContinues() async throws {
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: StateMachineStreamingEngine(finalText: "本地文本"),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            llmOptimizationService: FailingLLMService(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: StateMachineHotkeyCoordinator()
        )
        appModel.updateLLMOptimizationEnabled(true)

        await appModel.startDictation()
        await appModel.finishDictation()

        XCTAssertEqual(appModel.sessionState, .readyToSubmit)
        XCTAssertEqual(appModel.lastTranscript, "本地文本")
    }

    func testStartFailureLeavesAppFailed() async {
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: StateMachineStreamingEngine(prepareError: TypeMoreError.transcriptionUnavailable),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: StateMachineHotkeyCoordinator()
        )

        await appModel.startDictation()

        XCTAssertEqual(appModel.sessionState, .failed)
    }

    func testInterruptDuringStartupResetsToIdle() async throws {
        let engine = StateMachineStreamingEngine(prepareDelayNanoseconds: 300_000_000)
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: engine,
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: StateMachineHotkeyCoordinator()
        )

        let startTask = Task { await appModel.startDictation() }
        try await Task.sleep(nanoseconds: 50_000_000)
        appModel.interruptCurrentFlow()
        await startTask.value

        XCTAssertEqual(appModel.sessionState, .idle)
    }

    func testFastSecondToggleDoesNotCreateCompletedSecondSession() async throws {
        let engine = StateMachineStreamingEngine(prepareDelayNanoseconds: 200_000_000)
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: engine,
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: StateMachineHotkeyCoordinator()
        )

        let first = Task { await appModel.toggleDictation() }
        try await Task.sleep(nanoseconds: 20_000_000)
        await appModel.toggleDictation()
        await first.value

        XCTAssertEqual(appModel.sessionState, .idle)
        let startSessionCount = await engine.startSessionCountSnapshot()
        XCTAssertEqual(startSessionCount, 0)
    }
}

private struct StateMachineAudioRecorder: AudioRecordingService {
    func startRecording() throws {}
    func stopRecording() throws -> RecordedAudio {
        RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/state-machine.wav"), duration: 1, sampleRate: 16_000, samplesRecorded: 16_000)
    }
}

private struct StateMachineLiveAudioRecorder: LiveAudioRecordingService {
    func startStreaming(
        keepDebugFile: Bool,
        onSamples: @escaping @Sendable ([Float], Double) -> Void,
        onStreamInterrupted: @escaping @Sendable (Error) -> Void
    ) throws {}

    func stopStreaming() throws -> LiveRecordingSummary {
        LiveRecordingSummary(fileURL: nil, duration: 1, sampleRate: 16_000, samplesRecorded: 16_000)
    }
}

private struct StateMachineTranscriptionEngine: TranscriptionEngine {
    func transcribe(audio: RecordedAudio, mode: DictationMode, language: TranscriptionLanguage) async throws -> String {
        "批量文本"
    }
}

private actor StateMachineStreamingEngine: StreamingSpeechEngine {
    private let finalText: String
    private let prepareError: Error?
    private let prepareDelayNanoseconds: UInt64
    private(set) var startSessionCount = 0

    init(finalText: String = "最终文本", prepareError: Error? = nil, prepareDelayNanoseconds: UInt64 = 0) {
        self.finalText = finalText
        self.prepareError = prepareError
        self.prepareDelayNanoseconds = prepareDelayNanoseconds
    }

    func prepare(dictionary: [DictionaryEntry], progress: @escaping @Sendable (SpeechModelState) -> Void) async throws -> SpeechModelState {
        if prepareDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: prepareDelayNanoseconds)
        }
        if let prepareError {
            throw prepareError
        }
        return .ready("test")
    }

    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        startSessionCount += 1
    }

    func acceptAudio(samples: [Float], sampleRate: Double) async {}

    func finish(recording: LiveRecordingSummary) async throws -> StreamingTranscriptionResult {
        StreamingTranscriptionResult(
            text: finalText,
            backend: .sherpaParaformer,
            duration: recording.duration,
            realTimeFactor: 0.01,
            firstPartialLatency: nil,
            finalizationLatency: 0.01,
            debugAudioURL: nil
        )
    }

    func cancel() async {}

    func startSessionCountSnapshot() -> Int {
        startSessionCount
    }
}

private actor RecordingTextInsertionService: TextInsertionService {
    private(set) var insertedTexts: [String] = []
    private(set) var returnCount = 0

    func insert(_ text: String, targetBundleIdentifier: String?) async throws {
        insertedTexts.append(text)
    }

    func sendReturn(targetBundleIdentifier: String?) async throws {
        returnCount += 1
    }

    func insertedTextsSnapshot() -> [String] {
        insertedTexts
    }

    func returnCountSnapshot() -> Int {
        returnCount
    }
}

private struct StateMachinePermissionCoordinator: PermissionCoordinator {
    var hasAccessibilityPermission: Bool { true }
    func ensureMicrophonePermission() async -> Bool { true }
    func openAccessibilityPrompt() {}
}

private struct StateMachineHotkeyCoordinator: HotkeyCoordinator {
    @MainActor
    func registerHotkeys(
        dictationHotkey: HotkeyDefinition,
        returnHotkey: HotkeyDefinition,
        cancelHotkey: HotkeyDefinition,
        onToggleDictation: @escaping () -> Void,
        onSendReturn: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> [HotkeyRegistrationResult] {
        []
    }
}

private struct PassthroughLLMService: LLMOptimizationService {
    func optimize(
        text: String,
        rawText: String,
        mode: DictationMode,
        profile: AppProfile,
        configuration: LLMOptimizationConfiguration
    ) async throws -> String {
        text
    }
}

private struct FailingLLMService: LLMOptimizationService {
    func optimize(
        text: String,
        rawText: String,
        mode: DictationMode,
        profile: AppProfile,
        configuration: LLMOptimizationConfiguration
    ) async throws -> String {
        throw TypeMoreError.transcriptionUnavailable
    }
}
