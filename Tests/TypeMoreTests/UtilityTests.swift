import XCTest
@testable import TypeMore

final class UtilityTests: XCTestCase {
    func testPasteboardRestoreRequiresUnchangedChangeCount() {
        XCTAssertTrue(PasteboardTextInsertionService.shouldRestorePasteboard(recordedChangeCount: 10, currentChangeCount: 10))
        XCTAssertFalse(PasteboardTextInsertionService.shouldRestorePasteboard(recordedChangeCount: 10, currentChangeCount: 11))
    }

    func testWithTimeoutReturnsCompletedValue() async throws {
        let value = try await withTimeout(seconds: 1, message: "timeout") {
            "done"
        }

        XCTAssertEqual(value, "done")
    }

    func testWithTimeoutThrowsOperationTimeout() async {
        do {
            _ = try await withTimeout(seconds: 0.01, message: "tiny timeout") {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout")
        } catch TypeMoreError.operationTimedOut(let message) {
            XCTAssertEqual(message, "tiny timeout")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHistoryStoreRecoversCorruptFile() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("history.json")
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = HistoryStore(fileURL: fileURL)

        let records = store.load()

        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNotNil(store.lastRecoveredCorruptFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.lastRecoveredCorruptFileURL!.path))
    }

    func testHistoryStoreAppliesRetention() throws {
        let fileURL = temporaryDirectory().appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: fileURL)
        let oldRecord = transcriptRecord(createdAt: Date().addingTimeInterval(-8 * 24 * 60 * 60), text: "old")
        let newRecord = transcriptRecord(createdAt: Date(), text: "new")

        store.save([oldRecord, newRecord], retention: .sevenDays)
        let reloaded = store.load(retention: .sevenDays)

        XCTAssertEqual(reloaded.map(\.text), ["new"])
    }

    func testSettingsStorePersistsHistoryRetention() {
        let suiteName = "TypeMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.historyRetention, .forever)
        store.historyRetention = .sevenDays

        XCTAssertEqual(SettingsStore(defaults: defaults).historyRetention, .sevenDays)
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

    private func transcriptRecord(createdAt: Date, text: String) -> TranscriptRecord {
        TranscriptRecord(
            text: text,
            rawText: text,
            mode: .general,
            targetApplicationName: "Tests",
            targetBundleIdentifier: "tests",
            createdAt: createdAt,
            duration: 1,
            inserted: true
        )
    }
}
