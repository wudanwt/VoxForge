import Foundation

enum AppDirectories {
    static func applicationSupport(
        fileManager: FileManager = .default,
        appending path: String? = nil
    ) -> URL {
        let baseURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        guard let path else { return baseURL }
        return baseURL.appendingPathComponent(path, isDirectory: true)
    }
}
