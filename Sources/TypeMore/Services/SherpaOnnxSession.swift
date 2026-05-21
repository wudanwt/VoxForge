import CSherpaShim
import Foundation

final class SherpaOnnxRecognizer: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(libraryURL: URL, modelPaths: SherpaModelPaths, hotwordsURL: URL?, numThreads: Int32 = 1) throws {
        var errorBuffer = [CChar](repeating: 0, count: 2048)
        let hotwordsPath = hotwordsURL?.path ?? ""
        let created = errorBuffer.withUnsafeMutableBufferPointer { errorPointer in
            libraryURL.path.withCString { libraryPath in
                modelPaths.encoder.path.withCString { encoderPath in
                    modelPaths.decoder.path.withCString { decoderPath in
                        modelPaths.tokens.path.withCString { tokensPath in
                            hotwordsPath.withCString { hotwords in
                                tm_sherpa_create_recognizer(
                                    libraryPath,
                                    encoderPath,
                                    decoderPath,
                                    tokensPath,
                                    hotwords,
                                    numThreads,
                                    errorPointer.baseAddress,
                                    Int32(errorPointer.count)
                                )
                            }
                        }
                    }
                }
            }
        }

        guard let created else {
            let message = String(cString: errorBuffer)
            throw TypeMoreError.sherpaRuntimeUnavailable(message.isEmpty ? "无法创建 sherpa recognizer。" : message)
        }
        handle = created
    }

    deinit {
        close()
    }

    var version: String {
        guard let handle, let pointer = tm_sherpa_version(handle), pointer.pointee != 0 else {
            return ""
        }
        return String(cString: pointer)
    }

    func createStreamSession() throws -> SherpaOnnxStreamSession {
        guard let handle else {
            throw TypeMoreError.recognitionBackendUnavailable("sherpa recognizer 尚未就绪。")
        }

        var errorBuffer = [CChar](repeating: 0, count: 2048)
        let created = errorBuffer.withUnsafeMutableBufferPointer { errorPointer in
            tm_sherpa_create_stream_session(handle, errorPointer.baseAddress, Int32(errorPointer.count))
        }

        guard let created else {
            let message = String(cString: errorBuffer)
            throw TypeMoreError.sherpaRuntimeUnavailable(message.isEmpty ? "无法创建 sherpa streaming session。" : message)
        }
        return SherpaOnnxStreamSession(handle: created, recognizer: self)
    }

    func close() {
        if let handle {
            tm_sherpa_destroy_recognizer(handle)
            self.handle = nil
        }
    }
}

final class SherpaOnnxStreamSession: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let recognizer: SherpaOnnxRecognizer

    fileprivate init(handle: OpaquePointer, recognizer: SherpaOnnxRecognizer) {
        self.handle = handle
        self.recognizer = recognizer
    }

    deinit {
        close()
    }

    func accept(samples: [Float], sampleRate: Double) {
        guard let handle, !samples.isEmpty else { return }
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            tm_sherpa_accept_waveform(handle, Int32(sampleRate.rounded()), baseAddress, Int32(pointer.count))
        }
    }

    func finish() {
        guard let handle else { return }
        let silence = [Float](repeating: 0, count: 16_000)
        accept(samples: silence, sampleRate: 16_000)
        tm_sherpa_finish(handle)
    }

    func currentText() -> String {
        guard let handle else { return "" }
        var textBuffer = [CChar](repeating: 0, count: 65_536)
        let count = textBuffer.withUnsafeMutableBufferPointer { pointer in
            tm_sherpa_copy_result(handle, pointer.baseAddress, Int32(pointer.count))
        }
        guard count > 0 else { return "" }
        return String(cString: textBuffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func close() {
        if let handle {
            tm_sherpa_destroy_stream_session(handle)
            self.handle = nil
        }
    }
}
