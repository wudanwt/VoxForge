import Foundation

struct SherpaRuntimeLocator {
    private static let libraryNames = [
        "libsherpa-onnx-c-api.dylib",
        "libsherpa-onnx.dylib"
    ]

    static func findRuntimeLibrary() -> URL? {
        if let explicit = ProcessInfo.processInfo.environment["TYPEMORE_SHERPA_LIBRARY_PATH"], !explicit.isEmpty {
            let url = URL(fileURLWithPath: explicit)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let candidateDirectories = [
            Bundle.main.privateFrameworksURL,
            Bundle.main.resourceURL,
            applicationSupportRuntimeDirectory(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/SherpaRuntime", isDirectory: true)
        ].compactMap { $0 }

        for directory in candidateDirectories {
            for name in libraryNames {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }

    static func applicationSupportRuntimeDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TypeMore/SherpaRuntime", isDirectory: true)
    }
}
