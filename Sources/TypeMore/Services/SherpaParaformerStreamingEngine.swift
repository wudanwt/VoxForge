import Foundation

actor SherpaParaformerStreamingEngine: StreamingTranscriptionEngine {
    private let modelManager: SherpaModelManager
    private let hotwordsStore: SherpaHotwordsStore
    private var recognizer: SherpaOnnxRecognizer?
    private var recognizerSignature: String?
    private var recognizerCreationTimedOut = false
    private var recognizerPreparationTask: Task<SherpaOnnxRecognizer, Error>?
    private var session: SherpaOnnxStreamSession?
    private var modelPaths: SherpaModelPaths?
    private var runtimeURL: URL?
    private var startedAt: Date?
    private var firstPartialAt: Date?
    private var finalizationStartedAt: Date?
    private var lastPartialText = ""
    private var onPartial: (@Sendable (String) -> Void)?

    init(
        modelManager: SherpaModelManager = SherpaModelManager(),
        hotwordsStore: SherpaHotwordsStore = SherpaHotwordsStore()
    ) {
        self.modelManager = modelManager
        self.hotwordsStore = hotwordsStore
    }

    func prepare(
        dictionary: [DictionaryEntry] = [],
        progress: @escaping @Sendable (SpeechModelState) -> Void
    ) async throws -> SpeechModelState {
        if let recognizer {
            return .ready(recognizer.version)
        }
        if recognizerCreationTimedOut {
            throw TypeMoreError.recognitionBackendUnavailable("上一次中文极速模型预热超时。为避免重复卡住，请重启 VoxForge 或切换识别引擎。")
        }
        guard let runtimeURL = SherpaRuntimeLocator.findRuntimeLibrary() else {
            throw TypeMoreError.sherpaRuntimeUnavailable("缺少 libsherpa-onnx-c-api.dylib。请先运行 script/setup_sherpa_onnx.sh，或把动态库放入 app 的 Frameworks。")
        }
        self.runtimeURL = runtimeURL
        let paths = try await modelManager.ensureModel(progress: progress)
        modelPaths = paths
        let hotwordsURL = try hotwordsStore.writeHotwords(dictionary: dictionary)
        let signature = hotwordSignature(dictionary)
        let preparedRecognizer: SherpaOnnxRecognizer
        if let task = recognizerPreparationTask {
            preparedRecognizer = try await task.value
        } else {
            progress(.ready("正在预热中文极速模型"))
            let task = Task {
                try await self.createRecognizerWithTimeout(
                    libraryURL: runtimeURL,
                    modelPaths: paths,
                    hotwordsURL: hotwordsURL,
                    timeout: 18
                )
            }
            recognizerPreparationTask = task
            do {
                preparedRecognizer = try await task.value
            } catch {
                recognizerPreparationTask = nil
                if case TypeMoreError.operationTimedOut = error {
                    recognizerCreationTimedOut = true
                }
                throw error
            }
            recognizerPreparationTask = nil
        }
        recognizer = preparedRecognizer
        recognizerSignature = signature
        return .ready(preparedRecognizer.version)
    }

    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        let activeRecognizer: SherpaOnnxRecognizer
        if let recognizer {
            activeRecognizer = recognizer
        } else {
            _ = try await prepare(dictionary: dictionary) { _ in }
            activeRecognizer = try recognizer.unwrap(or: TypeMoreError.recognitionBackendUnavailable("中文极速 recognizer 尚未就绪。"))
        }
        if recognizerSignature != hotwordSignature(dictionary) {
            // Keep the current recognizer for stability; updated hotwords take effect after refresh/restart.
        }
        let createdSession = try activeRecognizer.createStreamSession()
        session = createdSession
        startedAt = Date()
        firstPartialAt = nil
        finalizationStartedAt = nil
        lastPartialText = ""
        self.onPartial = onPartial
    }

    func acceptAudio(samples: [Float], sampleRate: Double) async {
        guard let session, !samples.isEmpty else { return }
        session.accept(samples: samples, sampleRate: sampleRate)
        let current = session.currentText()
        guard !current.isEmpty, current != lastPartialText else { return }
        if firstPartialAt == nil {
            firstPartialAt = Date()
        }
        lastPartialText = current
        onPartial?(current)
    }

    func finish(recording: LiveRecordingSummary) async throws -> StreamingTranscriptionResult {
        guard let session else {
            throw TypeMoreError.transcriptionUnavailable
        }
        let finalStart = Date()
        finalizationStartedAt = finalStart
        session.finish()
        let text = session.currentText()
        session.close()
        self.session = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let duration = String(format: "%.2f", recording.duration)
            throw TypeMoreError.recognitionBackendUnavailable(
                "中文极速没有识别到文本。录音时长 \(duration)s，样本数 \(recording.samplesRecorded)。请确认麦克风输入正常，并至少说 1 秒以上。"
            )
        }

        let finalizationLatency = Date().timeIntervalSince(finalStart)
        let duration = recording.duration
        let processingDuration = Date().timeIntervalSince(finalStart)
        let realTimeFactor = duration > 0 ? processingDuration / duration : 0
        let firstPartialLatency = firstPartialAt.flatMap { startedAt?.distance(to: $0) }

        return StreamingTranscriptionResult(
            text: trimmed,
            backend: .sherpaParaformer,
            duration: duration,
            realTimeFactor: realTimeFactor,
            firstPartialLatency: firstPartialLatency,
            finalizationLatency: finalizationLatency,
            debugAudioURL: recording.fileURL
        )
    }

    func cancel() async {
        session?.close()
        session = nil
        startedAt = nil
        firstPartialAt = nil
        finalizationStartedAt = nil
        lastPartialText = ""
        onPartial = nil
    }

    func invalidatePreparedRecognizer() {
        session?.close()
        session = nil
        recognizer?.close()
        recognizer = nil
        recognizerSignature = nil
        recognizerCreationTimedOut = false
        recognizerPreparationTask?.cancel()
        recognizerPreparationTask = nil
    }

    private nonisolated func createRecognizerWithTimeout(
        libraryURL: URL,
        modelPaths: SherpaModelPaths,
        hotwordsURL: URL?,
        timeout: TimeInterval
    ) async throws -> SherpaOnnxRecognizer {
        let task = Task.detached(priority: .userInitiated) {
            do {
                return try SherpaOnnxRecognizer(
                    libraryURL: libraryURL,
                    modelPaths: modelPaths,
                    hotwordsURL: hotwordsURL,
                    numThreads: 1
                )
            } catch {
                return try SherpaOnnxRecognizer(
                    libraryURL: libraryURL,
                    modelPaths: modelPaths,
                    hotwordsURL: nil,
                    numThreads: 1
                )
            }
        }

        return try await withTimeout(
            seconds: timeout,
            message: "sherpa-onnx 预热 Paraformer recognizer 超时。请重启 VoxForge 或切换识别引擎。"
        ) {
            try await task.value
        }
    }

    private func hotwordSignature(_: [DictionaryEntry]) -> String {
        ""
    }

    private nonisolated func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        message: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let task = Task {
            try await operation()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let lock = NSLock()
                var didResume = false

                func resume(_ result: Result<T, Error>) {
                    lock.lock()
                    guard !didResume else {
                        lock.unlock()
                        return
                    }
                    didResume = true
                    lock.unlock()

                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                Task {
                    do {
                        resume(.success(try await task.value))
                    } catch {
                        resume(.failure(error))
                    }
                }

                Task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    task.cancel()
                    resume(.failure(TypeMoreError.operationTimedOut(message)))
                }
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private extension Optional {
    func unwrap(or error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
