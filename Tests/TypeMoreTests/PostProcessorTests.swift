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
}
