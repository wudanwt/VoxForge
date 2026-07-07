import Foundation

final class HistoryStore {
    private let fileURL: URL
    private let diagnosticsRecorder: DiagnosticsRecorder?
    private(set) var lastRecoveredCorruptFileURL: URL?

    init(fileURL: URL? = nil, diagnosticsRecorder: DiagnosticsRecorder? = nil) {
        self.diagnosticsRecorder = diagnosticsRecorder
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = AppDirectories.applicationSupport(appending: "TypeMore")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("history.json")
        }
    }

    func load(retention: HistoryRetention = .forever) -> [TranscriptRecord] {
        lastRecoveredCorruptFileURL = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([TranscriptRecord].self, from: data)
            return filter(records, retention: retention)
        } catch {
            lastRecoveredCorruptFileURL = recoverCorruptHistoryFile()
            diagnosticsRecorder?.record(DiagnosticEvent(
                category: .dictation,
                phase: "history.load.failed",
                error: error.localizedDescription,
                details: ["recoveredPath": lastRecoveredCorruptFileURL?.path ?? ""]
            ))
            return []
        }
    }

    func save(_ records: [TranscriptRecord], retention: HistoryRetention = .forever) {
        let trimmed = Array(filter(records, retention: retention).prefix(200))
        do {
            let data = try JSONEncoder().encode(trimmed)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            diagnosticsRecorder?.record(DiagnosticEvent(
                category: .dictation,
                phase: "history.save.failed",
                error: error.localizedDescription
            ))
        }
    }

    private func filter(_ records: [TranscriptRecord], retention: HistoryRetention) -> [TranscriptRecord] {
        guard let cutoff = retention.cutoffDate else { return records }
        return records.filter { $0.createdAt >= cutoff }
    }

    private func recoverCorruptHistoryFile() -> URL? {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let recoveredURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("history.corrupt-\(timestamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: recoveredURL)
            return recoveredURL
        } catch {
            diagnosticsRecorder?.record(DiagnosticEvent(
                category: .dictation,
                phase: "history.corrupt_recovery.failed",
                error: error.localizedDescription
            ))
            return nil
        }
    }
}
