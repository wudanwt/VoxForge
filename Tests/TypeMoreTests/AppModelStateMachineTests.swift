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
            sherpaStreamingEngine: StateMachineStreamingEngine(finalText: "用 swift ui"),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            llmOptimizationService: FailingLLMService(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: StateMachineHotkeyCoordinator()
        )
        appModel.personalDictionary = [
            DictionaryEntry(term: "SwiftUI", aliases: ["swift ui"], behavior: .fixed)
        ]
        appModel.updateLLMOptimizationEnabled(true)

        await appModel.startDictation()
        await appModel.finishDictation()

        XCTAssertEqual(appModel.sessionState, .readyToSubmit)
        XCTAssertEqual(appModel.lastTranscript, "用 SwiftUI")
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

    func testBridgeModeUsesTwoDictationShortcutsThenReturnAndRepeats() async {
        let settingsStore = isolatedSettingsStore()
        settingsStore.applicationOperatingMode = .djiHotkeyBridge
        let targetHotkey = HotkeyDefinition(keyCode: 49, modifiers: HotkeyDefinition.defaultDictation.modifiers)
        settingsStore.bridgeTargetHotkey = targetHotkey
        let sender = RecordingSyntheticHotkeySender()
        let engine = StateMachineStreamingEngine()
        let hotkeyCoordinator = RecordingHotkeyCoordinator()
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: engine,
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: hotkeyCoordinator,
            syntheticHotkeySender: sender,
            settingsStore: settingsStore
        )

        appModel.configureHotkeysIfNeeded()
        appModel.prewarmDefaultRecognitionBackendIfNeeded()
        await appModel.handleExternalPrimaryTrigger()
        XCTAssertEqual(appModel.bridgeClickStep, .stopDictation)
        await appModel.handleExternalPrimaryTrigger()
        XCTAssertEqual(appModel.bridgeClickStep, .sendReturn)
        await appModel.handleExternalPrimaryTrigger()

        let prepareCount = await engine.prepareCountSnapshot()
        let startSessionCount = await engine.startSessionCountSnapshot()
        XCTAssertEqual(sender.sentHotkeys, [targetHotkey, targetHotkey, .plainReturn])
        XCTAssertEqual(appModel.bridgeClickStep, .startDictation)
        XCTAssertEqual(appModel.sessionState, .idle)
        XCTAssertEqual(hotkeyCoordinator.registerCount, 0)
        XCTAssertEqual(hotkeyCoordinator.unregisterCount, 1)
        XCTAssertEqual(prepareCount, 0)
        XCTAssertEqual(startSessionCount, 0)
    }

    func testFullModeDJITriggerStillStartsInternalDictation() async {
        let sender = RecordingSyntheticHotkeySender()
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: StateMachineStreamingEngine(),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: RecordingHotkeyCoordinator(),
            syntheticHotkeySender: sender,
            settingsStore: isolatedSettingsStore()
        )

        await appModel.handleExternalPrimaryTrigger()

        XCTAssertEqual(appModel.sessionState, .recording)
        XCTAssertTrue(sender.sentHotkeys.isEmpty)
    }

    func testSwitchingModesInterruptsRecordingAndUnregistersThenRestoresHotkeys() async {
        let hotkeyCoordinator = RecordingHotkeyCoordinator()
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: StateMachineStreamingEngine(),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: hotkeyCoordinator,
            syntheticHotkeySender: RecordingSyntheticHotkeySender(),
            settingsStore: isolatedSettingsStore()
        )
        appModel.configureHotkeysIfNeeded()
        await appModel.startDictation()
        XCTAssertEqual(appModel.sessionState, .recording)

        appModel.updateApplicationOperatingMode(.djiHotkeyBridge)

        XCTAssertEqual(appModel.sessionState, .idle)
        XCTAssertEqual(hotkeyCoordinator.unregisterCount, 1)
        XCTAssertEqual(appModel.hotkeyStatusMessage, "桥接模式下已停用 VoxForge 全局快捷键")

        appModel.updateApplicationOperatingMode(.fullDictation)

        XCTAssertEqual(hotkeyCoordinator.registerCount, 2)
        XCTAssertEqual(appModel.applicationOperatingMode, .fullDictation)
    }

    func testBridgeHotkeyFailureIsVisible() {
        let settingsStore = isolatedSettingsStore()
        settingsStore.applicationOperatingMode = .djiHotkeyBridge
        let sender = RecordingSyntheticHotkeySender(error: SyntheticHotkeySenderError.eventCreationFailed)
        let appModel = AppModel(
            audioRecorder: StateMachineAudioRecorder(),
            transcriptionEngine: StateMachineTranscriptionEngine(),
            sherpaStreamingEngine: StateMachineStreamingEngine(),
            streamingAudioRecorder: StateMachineLiveAudioRecorder(),
            textInsertionService: RecordingTextInsertionService(),
            permissionCoordinator: StateMachinePermissionCoordinator(),
            hotkeyCoordinator: RecordingHotkeyCoordinator(),
            syntheticHotkeySender: sender,
            settingsStore: settingsStore
        )

        appModel.sendBridgeTargetHotkey()

        XCTAssertTrue(appModel.bridgeStatusMessage.contains("发送失败"))
        XCTAssertTrue(appModel.errorMessage?.contains("无法发送目标快捷键") == true)
        XCTAssertEqual(appModel.bridgeClickStep, .startDictation)
    }

    private func isolatedSettingsStore() -> SettingsStore {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return SettingsStore(defaults: defaults)
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
    private(set) var prepareCount = 0
    private(set) var startSessionCount = 0

    init(finalText: String = "最终文本", prepareError: Error? = nil, prepareDelayNanoseconds: UInt64 = 0) {
        self.finalText = finalText
        self.prepareError = prepareError
        self.prepareDelayNanoseconds = prepareDelayNanoseconds
    }

    func prepare(dictionary: [DictionaryEntry], progress: @escaping @Sendable (SpeechModelState) -> Void) async throws -> SpeechModelState {
        prepareCount += 1
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

    func prepareCountSnapshot() -> Int {
        prepareCount
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

    @MainActor
    func unregisterHotkeys() {}
}

@MainActor
private final class RecordingHotkeyCoordinator: HotkeyCoordinator {
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func registerHotkeys(
        dictationHotkey: HotkeyDefinition,
        returnHotkey: HotkeyDefinition,
        cancelHotkey: HotkeyDefinition,
        onToggleDictation: @escaping () -> Void,
        onSendReturn: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> [HotkeyRegistrationResult] {
        registerCount += 1
        return []
    }

    func unregisterHotkeys() {
        unregisterCount += 1
    }
}

private final class RecordingSyntheticHotkeySender: SyntheticHotkeySending {
    private(set) var sentHotkeys: [HotkeyDefinition] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func send(_ hotkey: HotkeyDefinition) throws {
        if let error {
            throw error
        }
        sentHotkeys.append(hotkey)
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
