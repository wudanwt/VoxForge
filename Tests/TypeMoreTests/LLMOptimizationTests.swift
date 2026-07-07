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
        store.setLLMPromptTemplate("通用模板 {cleanedText}", for: .general)
        store.setLLMPromptTemplate("编程模板 {app}", for: .codingPrompt)
        store.keepDebugRecordings = true
        store.transcriptionLanguage = .auto
        store.recognitionBackend = .whisperKitStreaming
        store.whisperKitStreamingModel = "large-v3"
        store.externalTriggerEnabled = true
        store.externalTriggerVendorID = 11427
        store.externalTriggerProductID = 16401
        store.externalTriggerSuppressVolume = false
        store.externalTriggerCancelModifier = .option
        store.personalDictionary = [
            DictionaryEntry(term: " 张三 ", aliases: [" 章三 ", ""], note: " 人名 "),
            DictionaryEntry(term: "", aliases: ["空词条"]),
            DictionaryEntry(term: "SwiftUI", aliases: ["swift ui"])
        ]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.llmOptimizationEnabled)
        XCTAssertEqual(reloaded.llmBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(reloaded.llmModel, "qwen3-coder")
        XCTAssertEqual(reloaded.llmStyleInstruction, "更像 Cursor prompt")
        XCTAssertEqual(reloaded.llmCustomPrompt, "编程模板 {app}")
        XCTAssertEqual(reloaded.llmPromptTemplate(for: .general), "通用模板 {cleanedText}")
        XCTAssertEqual(reloaded.llmPromptTemplate(for: .codingPrompt), "编程模板 {app}")
        XCTAssertEqual(reloaded.llmPromptTemplate(for: .literal), "")
        XCTAssertTrue(reloaded.keepDebugRecordings)
        XCTAssertEqual(reloaded.transcriptionLanguage, .auto)
        XCTAssertEqual(reloaded.recognitionBackend, .whisperKitStreaming)
        XCTAssertEqual(reloaded.whisperKitStreamingModel, "large-v3")
        XCTAssertTrue(reloaded.externalTriggerEnabled)
        XCTAssertEqual(reloaded.externalTriggerVendorID, 11427)
        XCTAssertEqual(reloaded.externalTriggerProductID, 16401)
        XCTAssertFalse(reloaded.externalTriggerSuppressVolume)
        XCTAssertEqual(reloaded.externalTriggerCancelModifier, .option)
        XCTAssertEqual(reloaded.personalDictionary.map(\.term), ["张三", "SwiftUI"])
        XCTAssertEqual(reloaded.personalDictionary.map(\.aliases), [["章三"], ["swift ui"]])
        XCTAssertEqual(reloaded.personalDictionary.first?.note, "人名")
    }

    func testSettingsStoreSanitizesAndResetsPersonalDictionary() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.personalDictionary = [
            DictionaryEntry(term: " VoxForge ", aliases: ["vox forge"]),
            DictionaryEntry(term: "voxforge", aliases: ["声铸"], note: " 应用名 "),
            DictionaryEntry(term: "", aliases: ["只有右边"])
        ]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.personalDictionary.count, 1)
        XCTAssertEqual(reloaded.personalDictionary.first?.term, "voxforge")
        XCTAssertEqual(reloaded.personalDictionary.first?.aliases, ["声铸"])
        XCTAssertEqual(reloaded.personalDictionary.first?.note, "应用名")

        reloaded.resetPersonalDictionary()
        XCTAssertEqual(reloaded.personalDictionary, DictionaryEntry.defaults)

        reloaded.personalDictionary = []
        XCTAssertEqual(SettingsStore(defaults: defaults).personalDictionary, [])
    }

    func testSettingsStoreRemovesLegacyVibeCodingDefaultEntry() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.personalDictionary = [
            DictionaryEntry(term: "vibe coding", note: "AI 编程工作流常用术语"),
            DictionaryEntry(term: "SwiftUI", aliases: ["swift ui"])
        ]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.personalDictionary.map(\.term), ["SwiftUI"])
        XCTAssertFalse(DictionaryEntry.defaults.contains { $0.term.caseInsensitiveCompare("vibe coding") == .orderedSame })
    }

    func testLegacyDictionaryEntryDecodesToTermAndAlias() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "spoken": "五律",
          "replacement": "吴律"
        }
        """

        let entry = try JSONDecoder().decode(DictionaryEntry.self, from: Data(json.utf8))

        XCTAssertEqual(entry.term, "吴律")
        XCTAssertEqual(entry.aliases, ["五律"])
        XCTAssertTrue(entry.note.isEmpty)
        XCTAssertTrue(entry.isEnabled)
    }

    func testDictionaryContextIncludesPersonalTermsForLLM() {
        let context = OpenAICompatibleOptimizationService.dictionaryContext(from: [
            DictionaryEntry(term: "吴律", aliases: ["五律", "无虑"], note: "我女儿名字，人名"),
            DictionaryEntry(term: "停用词", aliases: ["不会出现"], isEnabled: false)
        ])

        XCTAssertTrue(context.contains("标准词条：吴律"))
        XCTAssertTrue(context.contains("常见误听：五律、无虑"))
        XCTAssertTrue(context.contains("说明：我女儿名字，人名"))
        XCTAssertFalse(context.contains("停用词"))
    }

    func testDictionaryContextSkipsTermsWithoutAliases() {
        let context = OpenAICompatibleOptimizationService.dictionaryContext(from: [
            DictionaryEntry(term: "vibe coding", note: "AI 编程工作流常用术语"),
            DictionaryEntry(term: "Xcode", aliases: ["x code"])
        ])

        XCTAssertFalse(context.contains("vibe coding"))
        XCTAssertTrue(context.contains("Xcode"))
    }

    func testDefaultPromptsAskLLMToFixSemanticTyposAndGrammar() {
        for mode in DictationMode.allCases {
            let prompt = OpenAICompatibleOptimizationService.defaultPromptTemplate(for: mode)

            XCTAssertTrue(prompt.contains("校验语义"))
            XCTAssertTrue(prompt.contains("错别字"))
            XCTAssertTrue(prompt.contains("同音误写"))
            XCTAssertTrue(prompt.contains("语病"))
            XCTAssertTrue(prompt.contains("术语"))
            XCTAssertTrue(prompt.contains("前后一致"))
            XCTAssertTrue(prompt.contains("口语赘余") || prompt.contains("无意义停顿"))
            XCTAssertTrue(prompt.contains("表达自己的意识"))
            XCTAssertTrue(prompt.contains("不要为了通顺而猜测"))
        }
    }

    func testCodingPromptMentionsVibeCodingConsistencyExample() {
        let prompt = OpenAICompatibleOptimizationService.defaultPromptTemplate(for: .codingPrompt)

        XCTAssertTrue(prompt.contains("vibe coding"))
        XCTAssertTrue(prompt.contains("web coding"))
        XCTAssertTrue(prompt.contains("外部 coding"))
        XCTAssertTrue(prompt.contains("不要误保留"))
        XCTAssertTrue(prompt.contains("表达自己的意识"))
        XCTAssertTrue(prompt.contains("表达自己的意思"))
        XCTAssertTrue(prompt.contains("你是不明确的"))
        XCTAssertTrue(prompt.contains("表达不够明确"))
    }

    func testRecognitionBackendSeparatesStreamingAndBatchWhisperKit() {
        XCTAssertTrue(RecognitionBackend.sherpaParaformer.isStreaming)
        XCTAssertTrue(RecognitionBackend.whisperKitStreaming.isStreaming)
        XCTAssertTrue(RecognitionBackend.appleDictation.isStreaming)
        XCTAssertFalse(RecognitionBackend.whisperKit.isStreaming)
        XCTAssertEqual(
            RecognitionBackend.selectableCases.contains(.appleDictation),
            RecognitionBackend.isAppleDictationSupported
        )
    }

    func testSettingsStoreMigratesUnavailableAppleBackendToSherpa() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(RecognitionBackend.appleDictation.rawValue, forKey: "recognitionBackend")

        let store = SettingsStore(defaults: defaults)
        if RecognitionBackend.isAppleDictationSupported {
            XCTAssertEqual(store.recognitionBackend, .appleDictation)
            XCTAssertEqual(defaults.string(forKey: "recognitionBackend"), RecognitionBackend.appleDictation.rawValue)
        } else {
            XCTAssertEqual(store.recognitionBackend, .sherpaParaformer)
            XCTAssertEqual(defaults.string(forKey: "recognitionBackend"), RecognitionBackend.sherpaParaformer.rawValue)
        }
    }

    func testSettingsStoreFallsBackFromLegacyCustomPromptForCodingTemplate() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("旧版编程提示词", forKey: "llmCustomPrompt")

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.llmPromptTemplate(for: .codingPrompt), "旧版编程提示词")
        XCTAssertEqual(store.llmPromptTemplate(for: .general), "")

        store.resetLLMPromptTemplate(for: .codingPrompt)
        XCTAssertEqual(store.llmPromptTemplate(for: .codingPrompt), "")
        XCTAssertEqual(store.llmCustomPrompt, "")
    }

    func testTranscriptionLanguageMapsToWhisperOptions() {
        XCTAssertEqual(TranscriptionLanguage.chinese.whisperLanguageCode, "zh")
        XCTAssertFalse(TranscriptionLanguage.chinese.shouldDetectLanguage)
        XCTAssertNil(TranscriptionLanguage.auto.whisperLanguageCode)
        XCTAssertTrue(TranscriptionLanguage.auto.shouldDetectLanguage)
        XCTAssertEqual(TranscriptionLanguage.english.whisperLanguageCode, "en")
    }
}
