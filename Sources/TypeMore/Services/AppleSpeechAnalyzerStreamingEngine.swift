import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(macOS 26.0, *)
actor AppleSpeechAnalyzerStreamingEngine: StreamingTranscriptionEngine {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Error>?
    private var selectedFormat: AVAudioFormat?
    private var startedAt: Date?
    private var firstPartialAt: Date?
    private var finalizationStartedAt: Date?
    private var nextInputFramePosition: Int64 = 0
    private var latestText = ""
    private var finalText = ""
    private var onPartial: (@Sendable (String) -> Void)?

    func prepare(
        dictionary: [DictionaryEntry] = [],
        progress: @escaping @Sendable (SpeechModelState) -> Void
    ) async throws -> SpeechModelState {
        let module = DictationTranscriber(locale: Locale(identifier: "zh_CN"), preset: .progressiveShortDictation)
        try await ensureAssets(for: module, progress: progress)
        return .ready("Apple SpeechAnalyzer")
    }

    func startSession(
        mode: DictationMode,
        language: TranscriptionLanguage,
        dictionary: [DictionaryEntry],
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        await cancel()

        let locale = await supportedLocale(for: language)
        let module = DictationTranscriber(
            locale: locale,
            contentHints: [.shortForm],
            transcriptionOptions: [.punctuation],
            reportingOptions: [.volatileResults, .frequentFinalization],
            attributeOptions: []
        )
        try await ensureAssets(for: module) { _ in }

        let modules: [any SpeechModule] = [module]
        let naturalFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules, considering: naturalFormat)
            ?? naturalFormat
        selectedFormat = audioFormat

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        try await analyzer.prepareToAnalyze(in: audioFormat)

        var continuation: AsyncStream<AnalyzerInput>.Continuation?
        let inputSequence = AsyncStream<AnalyzerInput> { streamContinuation in
            continuation = streamContinuation
        }

        self.analyzer = analyzer
        self.transcriber = module
        inputContinuation = continuation
        startedAt = Date()
        firstPartialAt = nil
        finalizationStartedAt = nil
        nextInputFramePosition = 0
        latestText = ""
        finalText = ""
        self.onPartial = onPartial

        resultsTask = Task { [weak self] in
            for try await result in module.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                await self?.record(text: text, isFinal: result.isFinal)
            }
        }

        analysisTask = Task {
            try await analyzer.start(inputSequence: inputSequence)
        }
    }

    func acceptAudio(samples: [Float], sampleRate: Double) async {
        guard !samples.isEmpty, let inputContinuation else { return }
        let format = selectedFormat ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        guard let buffer = pcmBuffer(samples: samples, sampleRate: sampleRate, outputFormat: format) else { return }
        guard buffer.frameLength > 0 else { return }
        let startTime = CMTime(value: nextInputFramePosition, timescale: CMTimeScale(buffer.format.sampleRate))
        nextInputFramePosition += Int64(buffer.frameLength)
        inputContinuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: startTime))
    }

    func finish(recording: LiveRecordingSummary) async throws -> StreamingTranscriptionResult {
        guard let analyzer else {
            throw TypeMoreError.transcriptionUnavailable
        }

        let finalStart = Date()
        finalizationStartedAt = finalStart
        inputContinuation?.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await analysisTask?.value
        try? await Task.sleep(nanoseconds: 150_000_000)
        resultsTask?.cancel()

        let text = (finalText.isEmpty ? latestText : finalText).trimmingCharacters(in: .whitespacesAndNewlines)
        await cancel()

        guard !text.isEmpty else {
            throw TypeMoreError.recognitionBackendUnavailable("Apple 原生听写没有返回文本。请确认系统语音模型已安装、麦克风输入正常，并至少说 1 秒以上。")
        }

        let finalizationLatency = Date().timeIntervalSince(finalStart)
        let processingDuration = Date().timeIntervalSince(finalStart)
        let realTimeFactor = recording.duration > 0 ? processingDuration / recording.duration : 0
        let firstPartialLatency = firstPartialAt.flatMap { startedAt?.distance(to: $0) }

        return StreamingTranscriptionResult(
            text: text,
            backend: .appleDictation,
            duration: recording.duration,
            realTimeFactor: realTimeFactor,
            firstPartialLatency: firstPartialLatency,
            finalizationLatency: finalizationLatency,
            debugAudioURL: recording.fileURL
        )
    }

    func cancel() async {
        inputContinuation?.finish()
        inputContinuation = nil
        analysisTask?.cancel()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        transcriber = nil
        selectedFormat = nil
        startedAt = nil
        firstPartialAt = nil
        finalizationStartedAt = nil
        nextInputFramePosition = 0
        latestText = ""
        finalText = ""
        onPartial = nil
    }

    private func record(text: String, isFinal: Bool) {
        if firstPartialAt == nil {
            firstPartialAt = Date()
        }
        latestText = text
        if isFinal {
            finalText = text
        }
        onPartial?(text)
    }

    private func ensureAssets(
        for module: DictationTranscriber,
        progress: @escaping @Sendable (SpeechModelState) -> Void
    ) async throws {
        let modules: [any SpeechModule] = [module]
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            try await reserveLocales(for: module)
            progress(.ready("Apple SpeechAnalyzer"))
            return
        case .unsupported:
            throw TypeMoreError.recognitionBackendUnavailable("当前系统或语言不支持 Apple 原生听写模型。")
        case .supported, .downloading:
            progress(.downloading(0))
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
                progress(.ready("Apple SpeechAnalyzer"))
                return
            }
            let progressTask = Task {
                while !Task.isCancelled {
                    progress(.downloading(request.progress.fractionCompleted))
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
            do {
                try await request.downloadAndInstall()
                try await reserveLocales(for: module)
                progressTask.cancel()
                progress(.ready("Apple SpeechAnalyzer"))
            } catch {
                progressTask.cancel()
                throw error
            }
        @unknown default:
            throw TypeMoreError.recognitionBackendUnavailable("Apple 原生听写模型状态未知。")
        }
    }

    private func reserveLocales(for module: DictationTranscriber) async throws {
        for locale in module.selectedLocales {
            try await AssetInventory.reserve(locale: locale)
        }
    }

    private func supportedLocale(for language: TranscriptionLanguage) async -> Locale {
        let preferred: Locale = {
            switch language {
            case .chinese, .auto:
                Locale(identifier: "zh_CN")
            case .english:
                Locale(identifier: "en_US")
            }
        }()
        return await DictationTranscriber.supportedLocale(equivalentTo: preferred) ?? preferred
    }

    private func pcmBuffer(samples: [Float], sampleRate: Double, outputFormat: AVAudioFormat?) -> AVAudioPCMBuffer? {
        guard let outputFormat else {
            return nil
        }

        if outputFormat.sampleRate == sampleRate,
           outputFormat.channelCount == 1,
           let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
           let channel = buffer.floatChannelData?[0] {
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
            return buffer
        }

        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            return nil
        }
        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = sourceBuffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
        }
        let ratio = outputFormat.sampleRate / sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 512
        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat),
              let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else {
            return nil
        }
        try? converter.convert(to: converted, from: sourceBuffer)
        return converted
    }
}
