import Foundation

final class SherpaModelManager {
    static let defaultSpec = SherpaModelSpec(
        directoryName: "sherpa-onnx-streaming-paraformer-bilingual-zh-en",
        archiveURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2")!,
        encoderName: "encoder.int8.onnx",
        decoderName: "decoder.int8.onnx",
        tokensName: "tokens.txt"
    )

    private let spec: SherpaModelSpec
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        spec: SherpaModelSpec = SherpaModelManager.defaultSpec,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.spec = spec
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("TypeMore/Models", isDirectory: true)
        }
    }

    var modelDirectory: URL {
        baseDirectory.appendingPathComponent(spec.directoryName, isDirectory: true)
    }

    func status() -> SpeechModelState {
        pathsIfPresent() == nil ? .missingModel : .ready("")
    }

    func pathsIfPresent() -> SherpaModelPaths? {
        let paths = paths()
        guard fileManager.fileExists(atPath: paths.encoder.path),
              fileManager.fileExists(atPath: paths.decoder.path),
              fileManager.fileExists(atPath: paths.tokens.path)
        else {
            return nil
        }
        return paths
    }

    func ensureModel(progress: @escaping @Sendable (SpeechModelState) -> Void) async throws -> SherpaModelPaths {
        if let existing = pathsIfPresent() {
            return existing
        }

        progress(.downloading(0))
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let archiveURL = baseDirectory.appendingPathComponent("\(spec.directoryName).tar.bz2")
        try await downloadArchive(to: archiveURL, progress: progress)
        progress(.downloading(1))
        try extractArchive(archiveURL)

        guard let downloaded = pathsIfPresent() else {
            throw TypeMoreError.sherpaModelMissing
        }
        return downloaded
    }

    private func downloadArchive(
        to archiveURL: URL,
        progress: @escaping @Sendable (SpeechModelState) -> Void
    ) async throws {
        let partialURL = archiveURL.appendingPathExtension("partial")
        var existingBytes = existingFileSize(at: partialURL)
        var request = URLRequest(url: spec.archiveURL)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TypeMoreError.modelDownloadFailed("模型下载没有返回 HTTP 响应。")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TypeMoreError.modelDownloadFailed("模型下载失败：HTTP \(httpResponse.statusCode)。")
        }

        let isResuming = httpResponse.statusCode == 206 && existingBytes > 0
        if !isResuming {
            existingBytes = 0
            if fileManager.fileExists(atPath: partialURL.path) {
                try fileManager.removeItem(at: partialURL)
            }
            fileManager.createFile(atPath: partialURL.path, contents: nil)
        }

        let expectedLength = expectedContentLength(response: httpResponse, alreadyDownloaded: existingBytes)
        let handle = try FileHandle(forWritingTo: partialURL)
        try handle.seekToEnd()
        defer {
            try? handle.close()
        }

        var downloaded = existingBytes
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                reportProgress(downloaded: downloaded, total: expectedLength, progress: progress)
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
            reportProgress(downloaded: downloaded, total: expectedLength, progress: progress)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.moveItem(at: partialURL, to: archiveURL)
    }

    private func existingFileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    private func expectedContentLength(response: HTTPURLResponse, alreadyDownloaded: Int64) -> Int64 {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let totalString = contentRange.split(separator: "/").last,
           let total = Int64(totalString) {
            return total
        }
        return response.expectedContentLength > 0 ? response.expectedContentLength + alreadyDownloaded : 0
    }

    private func reportProgress(
        downloaded: Int64,
        total: Int64,
        progress: @escaping @Sendable (SpeechModelState) -> Void
    ) {
        guard total > 0 else {
            progress(.downloading(0))
            return
        }
        let fraction = min(max(Double(downloaded) / Double(total), 0), 1)
        progress(.downloading(fraction))
    }

    private func paths() -> SherpaModelPaths {
        let directory = modelDirectory
        return SherpaModelPaths(
            directory: directory,
            encoder: directory.appendingPathComponent(spec.encoderName),
            decoder: directory.appendingPathComponent(spec.decoderName),
            tokens: directory.appendingPathComponent(spec.tokensName)
        )
    }

    private func extractArchive(_ archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveURL.path, "-C", baseDirectory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TypeMoreError.sherpaModelExtractionFailed
        }
    }
}

struct SherpaModelSpec: Sendable, Equatable {
    var directoryName: String
    var archiveURL: URL
    var encoderName: String
    var decoderName: String
    var tokensName: String
}
