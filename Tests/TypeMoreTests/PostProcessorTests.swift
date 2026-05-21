import XCTest
@testable import TypeMore

final class PostProcessorTests: XCTestCase {
    func testCodingPromptRemovesFillersAndKeepsSwiftUITerm() {
        let processor = CodingPromptPostProcessor()
        let result = processor.process(
            "呃，帮我重构这个 Swift UI 视图，然后呢 补充单元测试。",
            mode: .codingPrompt,
            profile: .generic,
            dictionary: DictionaryEntry.defaults
        )

        XCTAssertFalse(result.contains("呃"))
        XCTAssertFalse(result.contains("然后呢"))
        XCTAssertTrue(result.contains("SwiftUI"))
        XCTAssertFalse(result.hasPrefix("，"))
    }

    func testLiteralModePreservesFillerWords() {
        let processor = CodingPromptPostProcessor()
        let result = processor.process(
            "呃 echo hello",
            mode: .literal,
            profile: .generic,
            dictionary: []
        )

        XCTAssertEqual(result, "呃 echo hello")
    }

    func testPersonalDictionaryReplacesCustomTerms() {
        let processor = CodingPromptPostProcessor()
        let result = processor.process(
            "请让章三修一下 swift ui 这个页面",
            mode: .general,
            profile: .generic,
            dictionary: [
                DictionaryEntry(term: "张三", aliases: ["章三"]),
                DictionaryEntry(term: "SwiftUI", aliases: ["swift ui"])
            ]
        )

        XCTAssertTrue(result.contains("张三"))
        XCTAssertFalse(result.contains("章三"))
        XCTAssertTrue(result.contains("SwiftUI"))
    }

    func testPersonalDictionaryIgnoresEmptyDraftEntries() {
        let processor = CodingPromptPostProcessor()
        let result = processor.process(
            "hello",
            mode: .literal,
            profile: .generic,
            dictionary: [
                DictionaryEntry(term: "", aliases: ["hello"]),
                DictionaryEntry(term: "不应该出现", aliases: [])
            ]
        )

        XCTAssertEqual(result, "hello")
    }

    func testPersonalDictionaryDoesNotReplaceStandardTermWithoutAlias() {
        let processor = CodingPromptPostProcessor()
        let result = processor.process(
            "我今天想写一首五律",
            mode: .general,
            profile: .generic,
            dictionary: [
                DictionaryEntry(term: "吴律", aliases: [], note: "我女儿名字")
            ]
        )

        XCTAssertEqual(result, "我今天想写一首五律")
    }

    func testDisabledPersonalDictionaryEntryDoesNotReplaceAlias() {
        let processor = CodingPromptPostProcessor()
        let result = processor.process(
            "今天五律要去上课",
            mode: .general,
            profile: .generic,
            dictionary: [
                DictionaryEntry(term: "吴律", aliases: ["五律"], note: "我女儿名字", isEnabled: false)
            ]
        )

        XCTAssertEqual(result, "今天五律要去上课")
    }
}
