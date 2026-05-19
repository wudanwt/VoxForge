import Foundation

final class HistoryStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = baseURL.appendingPathComponent("TypeMore", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("history.json")
        }
    }

    func load() -> [TranscriptRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([TranscriptRecord].self, from: data)) ?? []
    }

    func save(_ records: [TranscriptRecord]) {
        let trimmed = Array(records.prefix(200))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
