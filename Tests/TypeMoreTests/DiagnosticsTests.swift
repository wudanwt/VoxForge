import Foundation
import XCTest
@testable import TypeMore

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticEventEncodingDoesNotContainSensitiveTranscriptOrPromptFields() throws {
        let event = DiagnosticEvent(
            category: .dictation,
            phase: "dictation.fail",
            operationID: UUID().uuidString,
            backend: "中文极速本地",
            mode: "编程提示词",
            language: "中文优先",
            targetAppName: "Cursor",
            targetBundleIdentifier: "com.example.Cursor",
            sessionState: "processing",
            message: "failed without transcript content",
            error: "timeout",
            details: ["safe": "metadata only"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(event), encoding: .utf8)!

        XCTAssertTrue(json.contains("dictation.fail"))
        XCTAssertFalse(json.contains("rawTranscript"))
        XCTAssertFalse(json.contains("cleanedText"))
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("prompt"))
    }

    func testDiagnosticsRecorderRotatesJSONLFiles() throws {
        let directory = temporaryDirectory()
        let recorder = DiagnosticsRecorder(
            directory: directory,
            subsystem: "TypeMoreTests",
            maxFileSize: 350,
            maxRotatedFiles: 2
        )

        for index in 0..<12 {
            recorder.record(DiagnosticEvent(
                category: .dictation,
                phase: "event.\(index)",
                message: String(repeating: "x", count: 120)
            ))
        }
        recorder.flush()

        let files = recorder.logFiles().map(\.lastPathComponent)
        XCTAssertTrue(files.contains("diagnostics.jsonl"))
        XCTAssertTrue(files.contains("diagnostics.1.jsonl"))
        XCTAssertLessThanOrEqual(files.count, 3)
    }

    func testDiagnosticsRecorderConcurrentWritesRemainValidJSONL() throws {
        let directory = temporaryDirectory()
        let recorder = DiagnosticsRecorder(directory: directory, subsystem: "TypeMoreTests")
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "TypeMoreTests.concurrentDiagnostics", attributes: .concurrent)

        for index in 0..<50 {
            group.enter()
            queue.async {
                recorder.record(DiagnosticEvent(category: .audio, phase: "audio.\(index)"))
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        recorder.flush()

        let content = try String(contentsOf: recorder.currentLogURL, encoding: .utf8)
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 50)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in lines {
            XCTAssertNoThrow(try decoder.decode(DiagnosticEvent.self, from: Data(String(line).utf8)))
        }
    }

    @MainActor
    func testPrepareTimeoutLogsFailureAndLeavesAppFailed() async throws {
        let directory = temporaryDirectory()
        let recorder = DiagnosticsRecorder(directory: directory, subsystem: "TypeMoreTests")
        let appModel = AppModel(
            audioRecorder: FakeAudioRecorder(),
            transcriptionEngine: FakeTranscriptionEngine(),
            sherpaStreamingEngine: TimeoutPrepareEngine(),
            streamingAudioRecorder: FakeLiveAudioRecorder(),
            diagnosticsRecorder: recorder,
            permissionCoordinator: AllowingPermissionCoordinator(),
            hotkeyCoordinator: NoopHotkeyCoordinator()
        )

        await appModel.startDictation()
        recorder.flush()

        XCTAssertEqual(appModel.sessionState, .failed)
        let content = try String(contentsOf: recorder.currentLogURL, encoding: .utf8)
        XCTAssertTrue(content.contains("recognition.prepare.start"))
        XCTAssertTrue(content.contains("recognition.prepare.failed"))
        XCTAssertTrue(content.contains("dictation.fail"))
    }

    func testSettingsStoreDefaultsDiagnosticAudioRetentionToOnFailure() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.diagnosticAudioRetentionPolicy, .onFailure)
        store.diagnosticAudioRetentionPolicy = .always
        XCTAssertEqual(SettingsStore(defaults: defaults).diagnosticAudioRetentionPolicy, .always)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeMoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct FakeAudioRecorder: AudioRecordingService {
    func startRecording() throws {}
    func stopRecording() throws -> RecordedAudio {
        RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/fake.wav"), duration: 0, sampleRate: 16_000, samplesRecorded: 0)
    }
}

private struct FakeLiveAudioRecorder: LiveAudioRecordingService {
    func startStreaming(
        keepDebugFile: Bool,
        onSamples: @escaping @Sendable ([Float], Double) -> Void,
        onStreamInterrupted: @escaping @Sendable (Error) -> Void
    ) throws {}
    func stopStreaming() throws -> LiveRecordingSummary {
        LiveRecordingSummary(fileURL: nil, duration: 0, sampleRate: 16_000, samplesRecorded: 0)
    }
}

private struct FakeTranscriptionEngine: TranscriptionEngine {
    func transcribe(audio: RecordedAudio, mode: DictationMode, language: TranscriptionLanguage) async throws -> String {
        "fake"
    }
}

private actor TimeoutPrepareEngine: StreamingSpeechEngine {
    func prepare(dictionary: [DictionaryEntry], progress: @escaping @Sendable (SpeechModelState) -> Void) async throws -> SpeechModelState {
        throw TypeMoreError.operationTimedOut("prepare timeout")
    }

    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {}

    func acceptAudio(samples: [Float], sampleRate: Double) async {}

    func finish(recording: LiveRecordingSummary) async throws -> StreamingTranscriptionResult {
        throw TypeMoreError.transcriptionUnavailable
    }

    func cancel() async {}
}

private struct AllowingPermissionCoordinator: PermissionCoordinator {
    var hasAccessibilityPermission: Bool { true }
    func ensureMicrophonePermission() async -> Bool { true }
    func openAccessibilityPrompt() {}
}

private struct NoopHotkeyCoordinator: HotkeyCoordinator {
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
