import Foundation
import OSLog

enum DiagnosticAudioRetentionPolicy: String, Codable, CaseIterable, Identifiable {
    case never
    case onFailure
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never:
            "不自动保留"
        case .onFailure:
            "失败时保留"
        case .always:
            "始终保留"
        }
    }
}

struct DiagnosticAudioSnapshot: Codable, Equatable, Sendable {
    var inputName: String?
    var inputUID: String?
    var sampleRate: Double
    var channelCount: Int
    var engineWasRunning: Bool

    var compactDescription: String {
        let name = inputName?.isEmpty == false ? inputName! : "Unknown input"
        return "\(name), \(Int(sampleRate)) Hz, \(channelCount) ch"
    }
}

struct DiagnosticFailureSummary: Codable, Equatable, Sendable {
    var timestamp: Date
    var phase: String
    var backend: String?
    var error: String
    var audioInput: String?
    var debugAudioPath: String?
}

struct DiagnosticEvent: Codable, Sendable {
    enum Category: String, Codable, Sendable {
        case dictation = "Dictation"
        case audio = "Audio"
        case recognition = "Recognition"
        case diagnostics = "Diagnostics"
    }

    var timestamp: Date
    var category: Category
    var phase: String
    var operationID: String?
    var backend: String?
    var mode: String?
    var language: String?
    var targetAppName: String?
    var targetBundleIdentifier: String?
    var sessionState: String?
    var activeDictationPath: String?
    var message: String?
    var error: String?
    var durationMs: Int?
    var timeoutSeconds: Double?
    var audio: DiagnosticAudioSnapshot?
    var samplesRecorded: Int?
    var debugAudioPath: String?
    var details: [String: String]

    init(
        timestamp: Date = Date(),
        category: Category,
        phase: String,
        operationID: String? = nil,
        backend: String? = nil,
        mode: String? = nil,
        language: String? = nil,
        targetAppName: String? = nil,
        targetBundleIdentifier: String? = nil,
        sessionState: String? = nil,
        activeDictationPath: String? = nil,
        message: String? = nil,
        error: String? = nil,
        durationMs: Int? = nil,
        timeoutSeconds: Double? = nil,
        audio: DiagnosticAudioSnapshot? = nil,
        samplesRecorded: Int? = nil,
        debugAudioPath: String? = nil,
        details: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.category = category
        self.phase = phase
        self.operationID = operationID
        self.backend = backend
        self.mode = mode
        self.language = language
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.sessionState = sessionState
        self.activeDictationPath = activeDictationPath
        self.message = message
        self.error = error
        self.durationMs = durationMs
        self.timeoutSeconds = timeoutSeconds
        self.audio = audio
        self.samplesRecorded = samplesRecorded
        self.debugAudioPath = debugAudioPath
        self.details = details
    }

    var failureSummary: DiagnosticFailureSummary? {
        guard let error else { return nil }
        return DiagnosticFailureSummary(
            timestamp: timestamp,
            phase: phase,
            backend: backend,
            error: error,
            audioInput: audio?.compactDescription,
            debugAudioPath: debugAudioPath
        )
    }
}

final class DiagnosticsRecorder: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.voxforge.diagnostics-recorder")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let subsystem: String
    private let maxFileSize: UInt64
    private let maxRotatedFiles: Int
    private(set) var lastFailureSummary: DiagnosticFailureSummary?

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.voxforge.app",
        maxFileSize: UInt64 = 2 * 1024 * 1024,
        maxRotatedFiles: Int = 5
    ) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.subsystem = subsystem
        self.maxFileSize = maxFileSize
        self.maxRotatedFiles = maxRotatedFiles
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.lastFailureSummary = loadMostRecentFailureSummary()
    }

    var logDirectory: URL { directory }
    var currentLogURL: URL { directory.appendingPathComponent("diagnostics.jsonl") }

    func record(_ event: DiagnosticEvent) {
        Logger(subsystem: subsystem, category: event.category.rawValue)
            .info("\(event.phase, privacy: .public) op=\(event.operationID ?? "-", privacy: .public) backend=\(event.backend ?? "-", privacy: .public) state=\(event.sessionState ?? "-", privacy: .public) message=\(event.message ?? event.error ?? "-", privacy: .public)")

        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
                try self.rotateIfNeeded()
                let data = try self.encoder.encode(event)
                let handle = try FileHandle(forWritingTo: self.currentLogURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data([0x0A]))
                try handle.close()
            } catch {
                Logger(subsystem: self.subsystem, category: DiagnosticEvent.Category.diagnostics.rawValue)
                    .error("Failed writing diagnostics: \(error.localizedDescription, privacy: .public)")
            }

            if let summary = event.failureSummary {
                self.lastFailureSummary = self.mergedFailureSummary(summary)
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    func clear() throws {
        queue.sync {
            if fileManager.fileExists(atPath: directory.path) {
                try? fileManager.removeItem(at: directory)
            }
            lastFailureSummary = nil
        }
    }

    func logFiles() -> [URL] {
        flush()
        let names = ((1...maxRotatedFiles).reversed().map { "diagnostics.\($0).jsonl" }) + ["diagnostics.jsonl"]
        return names
            .map { directory.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    func recentFailureSummary() -> DiagnosticFailureSummary? {
        flush()
        return lastFailureSummary ?? loadMostRecentFailureSummary()
    }

    static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        AppDirectories.applicationSupport(fileManager: fileManager, appending: "TypeMore/Diagnostics")
    }

    private func rotateIfNeeded() throws {
        guard fileManager.fileExists(atPath: currentLogURL.path) else {
            fileManager.createFile(atPath: currentLogURL.path, contents: nil)
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: currentLogURL.path)
        let size = attributes[.size] as? UInt64 ?? 0
        guard size >= maxFileSize else { return }

        let oldest = directory.appendingPathComponent("diagnostics.\(maxRotatedFiles).jsonl")
        if fileManager.fileExists(atPath: oldest.path) {
            try fileManager.removeItem(at: oldest)
        }

        if maxRotatedFiles > 1 {
            for index in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
                let source = directory.appendingPathComponent("diagnostics.\(index).jsonl")
                let destination = directory.appendingPathComponent("diagnostics.\(index + 1).jsonl")
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: destination)
                }
            }
        }

        let first = directory.appendingPathComponent("diagnostics.1.jsonl")
        try fileManager.moveItem(at: currentLogURL, to: first)
        fileManager.createFile(atPath: currentLogURL.path, contents: nil)
    }

    private func loadMostRecentFailureSummary() -> DiagnosticFailureSummary? {
        for file in logFilesWithoutFlush().reversed() {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n").reversed() {
                guard let data = String(line).data(using: .utf8),
                      let event = try? decoder.decode(DiagnosticEvent.self, from: data),
                      let summary = event.failureSummary
                else { continue }
                return summary
            }
        }
        return nil
    }

    private func mergedFailureSummary(_ summary: DiagnosticFailureSummary) -> DiagnosticFailureSummary {
        guard let lastFailureSummary else { return summary }
        return DiagnosticFailureSummary(
            timestamp: summary.timestamp,
            phase: summary.phase,
            backend: summary.backend ?? lastFailureSummary.backend,
            error: summary.error,
            audioInput: summary.audioInput ?? lastFailureSummary.audioInput,
            debugAudioPath: summary.debugAudioPath ?? lastFailureSummary.debugAudioPath
        )
    }

    private func logFilesWithoutFlush() -> [URL] {
        let names = ((1...maxRotatedFiles).reversed().map { "diagnostics.\($0).jsonl" }) + ["diagnostics.jsonl"]
        return names
            .map { directory.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }
}
