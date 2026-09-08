import XCTest
@testable import TypeMore

final class PersonalDictionaryProcessorTests: XCTestCase {
    private let processor = PersonalDictionaryProcessor()

    func testFixedReplacementUsesLongestMatchWithoutCascading() {
        let entries = [
            DictionaryEntry(term: "SwiftUI", aliases: ["swift ui"], behavior: .fixed),
            DictionaryEntry(term: "UI", aliases: ["ui"], behavior: .fixed),
            DictionaryEntry(term: "最终", aliases: ["SwiftUI"], behavior: .fixed)
        ]

        let result = processor.process(
            "用 swift ui 写界面",
            entries: entries,
            targetBundleIdentifier: "com.example.editor"
        )

        XCTAssertEqual(result.text, "用 SwiftUI 写界面")
        XCTAssertEqual(result.replacementCount, 1)
    }

    func testEnglishAliasRequiresWordBoundariesAndIgnoresCase() {
        let entry = DictionaryEntry(term: "UI", aliases: ["ui"], behavior: .fixed)

        let result = processor.process(
            "UI SwiftUI ui_test ui",
            entries: [entry],
            targetBundleIdentifier: "*"
        )

        XCTAssertEqual(result.text, "UI SwiftUI ui_test UI")
    }

    func testApplicationScopeAndDisabledEntriesAreRespected() {
        let scoped = DictionaryEntry(
            term: "项目甲",
            aliases: ["项目加"],
            behavior: .fixed,
            scope: DictionaryEntryScope(applicationBundleIdentifiers: ["com.example.editor"])
        )
        let disabled = DictionaryEntry(term: "吴律", aliases: ["五律"], isEnabled: false, behavior: .fixed)

        XCTAssertEqual(
            processor.process("项目加和五律", entries: [scoped, disabled], targetBundleIdentifier: "com.example.browser").text,
            "项目加和五律"
        )
        XCTAssertEqual(
            processor.process("项目加和五律", entries: [scoped, disabled], targetBundleIdentifier: "com.example.editor").text,
            "项目甲和五律"
        )
    }

    func testValidationAllowsSameAliasForDisjointApplicationsButRejectsOverlappingScopes() {
        let editor = DictionaryEntry(
            term: "项目甲",
            aliases: ["项目"],
            behavior: .fixed,
            scope: DictionaryEntryScope(applicationBundleIdentifiers: ["com.example.editor"])
        )
        let browser = DictionaryEntry(
            term: "项目乙",
            aliases: ["项目"],
            behavior: .fixed,
            scope: DictionaryEntryScope(applicationBundleIdentifiers: ["com.example.browser"])
        )

        XCTAssertNil(SettingsStore.dictionaryValidationError(in: [editor, browser]))
        XCTAssertNotNil(SettingsStore.dictionaryValidationError(in: [
            editor,
            DictionaryEntry(term: "项目乙", aliases: ["项目"], behavior: .fixed)
        ]))
    }
}
