import Foundation

actor SherpaParaformerStreamingEngine: StreamingTranscriptionEngine {
    private let modelManager: SherpaModelManager
    private let hotwordsStore: SherpaHotwordsStore
    private var session: SherpaOnnxSession?
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

    func prepare(progress: @escaping @Sendable (SpeechModelState) -> Void) async throws -> SpeechModelState {
        guard let runtimeURL = SherpaRuntimeLocator.findRuntimeLibrary() else {
            throw TypeMoreError.sherpaRuntimeUnavailable("缺少 libsherpa-onnx-c-api.dylib。请先运行 script/setup_sherpa_onnx.sh，或把动态库放入 app 的 Frameworks。")
        }
        self.runtimeURL = runtimeURL
        let paths = try await modelManager.ensureModel(progress: progress)
        modelPaths = paths
        return .ready("")
    }

    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let runtimeURL = runtimeURL ?? SherpaRuntimeLocator.findRuntimeLibrary() else {
            throw TypeMoreError.sherpaRuntimeUnavailable("缺少 sherpa-onnx 动态库。")
        }
        let paths = try modelPaths ?? modelManager.pathsIfPresent().unwrap(or: TypeMoreError.sherpaModelMissing)
        let hotwordsURL = try hotwordsStore.writeHotwords(dictionary: dictionary)
        let createdSession: SherpaOnnxSession
        do {
            createdSession = try SherpaOnnxSession(
                libraryURL: runtimeURL,
                modelPaths: paths,
                hotwordsURL: hotwordsURL,
                numThreads: 1
            )
        } catch {
            createdSession = try SherpaOnnxSession(
                libraryURL: runtimeURL,
                modelPaths: paths,
                hotwordsURL: nil,
                numThreads: 1
            )
        }
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
}

private extension Optional {
    func unwrap(or error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
