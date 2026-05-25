import Foundation

struct DiagnosticEnvironment: Codable, Sendable {
    var exportedAt: Date
    var appVersion: String
    var buildVersion: String
    var operatingSystem: String
    var recognitionBackend: String
    var mode: String
    var language: String
    var modelStatus: String
    var keepDebugRecordings: Bool
    var audioRetentionPolicy: String
    var recentFailure: DiagnosticFailureSummary?
}

struct DiagnosticExportResult: Sendable {
    var packageURL: URL
    var includedAudioFiles: Int
}

final class DiagnosticPackageExporter {
    private let recorder: DiagnosticsRecorder
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(recorder: DiagnosticsRecorder, fileManager: FileManager = .default) {
        self.recorder = recorder
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func exportPackage(
        environment: DiagnosticEnvironment,
        audioFileURLs: [URL]
    ) throws -> DiagnosticExportResult {
        recorder.flush()

        let exportDirectory = recorder.logDirectory.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let timestamp = Self.filenameTimestamp(from: Date())
        let stagingURL = exportDirectory.appendingPathComponent("VoxForgeDiagnostics-\(timestamp)", isDirectory: true)
        let zipURL = exportDirectory.appendingPathComponent("VoxForgeDiagnostics-\(timestamp).zip")

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try writeEnvironment(environment, to: stagingURL)
        try writeReadme(audioFileURLs: audioFileURLs, to: stagingURL)
        try copyLogs(to: stagingURL)
        let audioCount = try copyAudioFiles(audioFileURLs, to: stagingURL)
        try createZip(from: stagingURL, to: zipURL)
        try? fileManager.removeItem(at: stagingURL)

        return DiagnosticExportResult(packageURL: zipURL, includedAudioFiles: audioCount)
    }

    private func writeEnvironment(_ environment: DiagnosticEnvironment, to stagingURL: URL) throws {
        let data = try encoder.encode(environment)
        try data.write(to: stagingURL.appendingPathComponent("environment.json"), options: .atomic)
    }

    private func writeReadme(audioFileURLs: [URL], to stagingURL: URL) throws {
        let message = """
        VoxForge Diagnostics

        This package contains diagnostic JSONL logs, a sanitized environment snapshot, and failed debug audio when available.
        It intentionally does not include raw transcript text, LLM prompts, API keys, or optimized text content.

        Included failed audio files: \(audioFileURLs.count)
        Logs are in logs/*.jsonl.
        """
        try message.write(to: stagingURL.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    private func copyLogs(to stagingURL: URL) throws {
        let logsURL = stagingURL.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsURL, withIntermediateDirectories: true)
        for file in recorder.logFiles() {
            let destination = logsURL.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file, to: destination)
        }
    }

    private func copyAudioFiles(_ audioFileURLs: [URL], to stagingURL: URL) throws -> Int {
        let existingFiles = audioFileURLs.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingFiles.isEmpty else { return 0 }

        let audioURL = stagingURL.appendingPathComponent("failed-audio", isDirectory: true)
        try fileManager.createDirectory(at: audioURL, withIntermediateDirectories: true)
        for file in existingFiles {
            let destination = audioURL.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: file, to: destination)
        }
        return existingFiles.count
    }

    private func createZip(from stagingURL: URL, to zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", stagingURL.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TypeMoreError.diagnosticExportFailed("ditto exited with status \(process.terminationStatus)")
        }
    }

    private static func filenameTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
