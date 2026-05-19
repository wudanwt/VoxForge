import Foundation
import XCTest
@testable import TypeMore

final class LLMOptimizationTests: XCTestCase {
    func testExtractOptimizedTextFromOpenAICompatibleResponse() throws {
        let json = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "请重构这个 SwiftUI 视图，并补充单元测试。"
              }
            }
          ]
        }
        """

        let text = try OpenAICompatibleOptimizationService.extractOptimizedText(from: Data(json.utf8))

        XCTAssertEqual(text, "请重构这个 SwiftUI 视图，并补充单元测试。")
    }

    func testSettingsStorePersistsLLMConfiguration() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.llmOptimizationEnabled = true
        store.llmBaseURL = "http://localhost:11434/v1"
        store.llmModel = "qwen3-coder"
        store.llmStyleInstruction = "更像 Cursor prompt"
        store.llmCustomPrompt = "把 {cleanedText} 改成适合 {app} 的最终输入。"
        store.keepDebugRecordings = true
        store.transcriptionLanguage = .auto
        store.recognitionBackend = .whisperKitStreaming
        store.whisperKitStreamingModel = "large-v3"
        store.externalTriggerEnabled = true
        store.externalTriggerVendorID = 11427
        store.externalTriggerProductID = 16401
        store.externalTriggerSuppressVolume = false
        store.externalTriggerCancelModifier = .option

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.llmOptimizationEnabled)
        XCTAssertEqual(reloaded.llmBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(reloaded.llmModel, "qwen3-coder")
        XCTAssertEqual(reloaded.llmStyleInstruction, "更像 Cursor prompt")
        XCTAssertEqual(reloaded.llmCustomPrompt, "把 {cleanedText} 改成适合 {app} 的最终输入。")
        XCTAssertTrue(reloaded.keepDebugRecordings)
        XCTAssertEqual(reloaded.transcriptionLanguage, .auto)
        XCTAssertEqual(reloaded.recognitionBackend, .whisperKitStreaming)
        XCTAssertEqual(reloaded.whisperKitStreamingModel, "large-v3")
        XCTAssertTrue(reloaded.externalTriggerEnabled)
        XCTAssertEqual(reloaded.externalTriggerVendorID, 11427)
        XCTAssertEqual(reloaded.externalTriggerProductID, 16401)
        XCTAssertFalse(reloaded.externalTriggerSuppressVolume)
        XCTAssertEqual(reloaded.externalTriggerCancelModifier, .option)
    }

    func testRecognitionBackendSeparatesStreamingAndBatchWhisperKit() {
        XCTAssertTrue(RecognitionBackend.sherpaParaformer.isStreaming)
        XCTAssertTrue(RecognitionBackend.whisperKitStreaming.isStreaming)
        XCTAssertFalse(RecognitionBackend.whisperKit.isStreaming)
        XCTAssertFalse(RecognitionBackend.appleDictation.isStreaming)
        XCTAssertFalse(RecognitionBackend.selectableCases.contains(.appleDictation))
    }

    func testSettingsStoreMigratesUnavailableAppleBackendToSherpa() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(RecognitionBackend.appleDictation.rawValue, forKey: "recognitionBackend")

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.recognitionBackend, .sherpaParaformer)
        XCTAssertEqual(defaults.string(forKey: "recognitionBackend"), RecognitionBackend.sherpaParaformer.rawValue)
    }

    func testTranscriptionLanguageMapsToWhisperOptions() {
        XCTAssertEqual(TranscriptionLanguage.chinese.whisperLanguageCode, "zh")
        XCTAssertFalse(TranscriptionLanguage.chinese.shouldDetectLanguage)
        XCTAssertNil(TranscriptionLanguage.auto.whisperLanguageCode)
        XCTAssertTrue(TranscriptionLanguage.auto.shouldDetectLanguage)
        XCTAssertEqual(TranscriptionLanguage.english.whisperLanguageCode, "en")
    }
}
