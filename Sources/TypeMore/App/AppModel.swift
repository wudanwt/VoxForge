import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var sessionState: DictationSessionState = .idle
    var selectedMode: DictationMode = .codingPrompt
    var statusMessage = "准备好听写"
    var lastTranscript = ""
    var lastTargetApplication: RunningApplicationInfo?
    var appProfiles: [AppProfile] = AppProfile.defaults
    var personalDictionary: [DictionaryEntry] = DictionaryEntry.defaults
    var transcriptionLanguage: TranscriptionLanguage
    var recognitionBackend: RecognitionBackend
    var speechModelState: SpeechModelState = .unchecked
    var saveHistory = true
    var historyRetention: HistoryRetention = .forever
    var launchAtLogin = false
    var modelStatus = "中文极速模型尚未检查"
    var errorMessage: String?
    var accessibilityPermissionGranted = false
    var transcriptRecords: [TranscriptRecord] = []
    var dictationHotkey: HotkeyDefinition
    var returnHotkey: HotkeyDefinition
    var cancelHotkey = HotkeyDefinition.defaultCancel
    var hotkeyStatusMessage = "快捷键尚未注册"
    var llmOptimizationEnabled: Bool
    var llmBaseURL: String
    var llmModel: String
    var llmStyleInstruction: String
    var llmCustomPrompt: String
    var llmPromptTemplateMode: DictationMode = .codingPrompt
    var llmAPIKey: String
    var keepDebugRecordings: Bool
    var diagnosticAudioRetentionPolicy: DiagnosticAudioRetentionPolicy
    var diagnosticStatusMessage = "诊断日志已就绪"
    var recentDiagnosticFailureSummary: DiagnosticFailureSummary?
    var lastDiagnosticPackageURL: URL?
    var whisperKitStreamingModel: String
    var externalTriggerEnabled: Bool
    var externalTriggerVendorID: Int
    var externalTriggerProductID: Int
    var externalTriggerSuppressVolume: Bool
    var externalTriggerCancelModifier: ExternalTriggerCancelModifier
    var externalTriggerStatus: ExternalTriggerStatus = .disabled
    var externalTriggerDevices: [ExternalTriggerDevice] = []
    var externalTriggerLastEvent: ExternalTriggerLastEvent?

    private let audioRecorder: AudioRecordingService
    private var streamingAudioRecorder: LiveAudioRecordingService
    private let transcriptionEngine: TranscriptionEngine
    private var sherpaStreamingEngine: StreamingSpeechEngine
    private var whisperKitStreamingEngine: StreamingSpeechEngine
    private var appleSpeechAnalyzerEngine: StreamingSpeechEngine?
    private let llmOptimizationService: LLMOptimizationService
    private let postProcessor: PostProcessingService
    private let textInsertionService: TextInsertionService
    private let permissionCoordinator: PermissionCoordinator
    private let hotkeyCoordinator: HotkeyCoordinator
    private let externalTriggerService: ExternalTriggerService
    private let diagnosticsRecorder: DiagnosticsRecorder
    private let diagnosticPackageExporter: DiagnosticPackageExporter
    private let foregroundApplicationTracker = ForegroundApplicationTracker()
    private let sherpaModelManager: SherpaModelManager
    private var recordingStart: Date?
    private var activeDictationPath: ActiveDictationPath?
    private let historyStore: HistoryStore
    private let settingsStore = SettingsStore()
    private let keychainStore = KeychainStore()
    private let hudController = DictationHUDController()
    private var activeOperationID: UUID?
    private var startupWatchdog: DispatchWorkItem?
    private var audioStartupWatchdog: DispatchWorkItem?
    private var lastAudioBufferOperationID: UUID?
    private var audioBufferContinuation: AsyncStream<AudioBuffer>.Continuation?
    private var audioBufferConsumerTask: Task<Void, Never>?
    private var sherpaPrewarmTask: Task<Void, Never>?
    private var deferredSherpaPrewarmTask: Task<Void, Never>?
    private var didStartAppServices = false
    private var suppressAutomaticPrewarmUntil: Date?
    private var hasLoadedLLMAPIKey = false

    init(
        audioRecorder: AudioRecordingService = AVAudioEngineRecordingService(),
        transcriptionEngine: TranscriptionEngine = WhisperKitTranscriptionEngine(),
        sherpaStreamingEngine: StreamingSpeechEngine? = nil,
        streamingAudioRecorder: LiveAudioRecordingService? = nil,
        whisperKitStreamingEngine: StreamingSpeechEngine? = nil,
        diagnosticsRecorder: DiagnosticsRecorder = DiagnosticsRecorder(),
        sherpaModelManager: SherpaModelManager = SherpaModelManager(),
        llmOptimizationService: LLMOptimizationService = OpenAICompatibleOptimizationService(),
        postProcessor: PostProcessingService = CodingPromptPostProcessor(),
        textInsertionService: TextInsertionService = PasteboardTextInsertionService(),
        permissionCoordinator: PermissionCoordinator = SystemPermissionCoordinator(),
        hotkeyCoordinator: HotkeyCoordinator = CarbonHotkeyCoordinator()
    ) {
        self.audioRecorder = audioRecorder
        self.diagnosticsRecorder = diagnosticsRecorder
        self.diagnosticPackageExporter = DiagnosticPackageExporter(recorder: diagnosticsRecorder)
        self.historyStore = HistoryStore(diagnosticsRecorder: diagnosticsRecorder)
        self.streamingAudioRecorder = streamingAudioRecorder ?? AVAudioEngineLiveRecordingService(diagnosticsRecorder: diagnosticsRecorder)
        self.transcriptionEngine = transcriptionEngine
        self.sherpaModelManager = sherpaModelManager
        self.sherpaStreamingEngine = sherpaStreamingEngine ?? SherpaParaformerStreamingEngine(modelManager: sherpaModelManager)
        let persistedWhisperKitModel = settingsStore.whisperKitStreamingModel
        self.whisperKitStreamingEngine = whisperKitStreamingEngine ?? WhisperKitStreamingEngine(modelName: persistedWhisperKitModel)
        if #available(macOS 26.0, *) {
            self.appleSpeechAnalyzerEngine = AppleSpeechAnalyzerStreamingEngine()
        } else {
            self.appleSpeechAnalyzerEngine = nil
        }
        self.llmOptimizationService = llmOptimizationService
        self.postProcessor = postProcessor
        self.textInsertionService = textInsertionService
        self.permissionCoordinator = permissionCoordinator
        self.hotkeyCoordinator = hotkeyCoordinator
        self.dictationHotkey = settingsStore.dictationHotkey
        self.returnHotkey = settingsStore.returnHotkey
        self.cancelHotkey = settingsStore.cancelHotkey
        self.saveHistory = settingsStore.saveHistory
        let persistedHistoryRetention = settingsStore.historyRetention
        self.historyRetention = persistedHistoryRetention
        self.selectedMode = settingsStore.selectedMode
        self.transcriptionLanguage = settingsStore.transcriptionLanguage
        let persistedBackend = settingsStore.recognitionBackend
        self.recognitionBackend = persistedBackend
        let initialSpeechModelState = sherpaModelManager.status()
        self.speechModelState = initialSpeechModelState
        self.modelStatus = initialSpeechModelState.title
        self.accessibilityPermissionGranted = permissionCoordinator.hasAccessibilityPermission
        self.transcriptRecords = historyStore.load(retention: persistedHistoryRetention)
        if let corruptURL = historyStore.lastRecoveredCorruptFileURL {
            self.statusMessage = "历史记录文件已损坏，已保留为 \(corruptURL.lastPathComponent)"
        }
        self.personalDictionary = settingsStore.personalDictionary
        self.llmOptimizationEnabled = settingsStore.llmOptimizationEnabled
        self.llmBaseURL = settingsStore.llmBaseURL
        self.llmModel = settingsStore.llmModel
        self.llmStyleInstruction = settingsStore.llmStyleInstruction
        self.llmCustomPrompt = settingsStore.llmCustomPrompt
        self.keepDebugRecordings = settingsStore.keepDebugRecordings
        self.diagnosticAudioRetentionPolicy = settingsStore.diagnosticAudioRetentionPolicy
        self.recentDiagnosticFailureSummary = diagnosticsRecorder.recentFailureSummary()
        self.whisperKitStreamingModel = persistedWhisperKitModel
        self.llmAPIKey = ""
        self.externalTriggerEnabled = settingsStore.externalTriggerEnabled
        self.externalTriggerVendorID = settingsStore.externalTriggerVendorID
        self.externalTriggerProductID = settingsStore.externalTriggerProductID
        self.externalTriggerSuppressVolume = settingsStore.externalTriggerSuppressVolume
        self.externalTriggerCancelModifier = settingsStore.externalTriggerCancelModifier
        self.externalTriggerService = ExternalTriggerService(configuration: ExternalTriggerService.Configuration(
            enabled: settingsStore.externalTriggerEnabled,
            vendorID: settingsStore.externalTriggerVendorID,
            productID: settingsStore.externalTriggerProductID,
            suppressVolume: settingsStore.externalTriggerSuppressVolume,
            cancelModifier: settingsStore.externalTriggerCancelModifier
        ))
        updateRecognitionBackendStatus(persistedBackend)
        configureExternalTrigger()
    }

    var primaryActionTitle: String {
        switch sessionState {
        case .idle, .failed:
            "开始听写"
        case .recording:
            "完成并输入"
        case .readyToSubmit:
            "发送回车"
        case .processing, .optimizing, .inserting:
            "处理中..."
        }
    }

    var menuBarSymbolName: String {
        switch sessionState {
        case .idle:
            "mic"
        case .recording:
            "record.circle"
        case .processing:
            "waveform"
        case .optimizing:
            "sparkles"
        case .inserting:
            "keyboard"
        case .readyToSubmit:
            "return"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var selectedProfile: AppProfile {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return .generic
        }
        return profile(for: bundleID)
    }

    private var shouldCaptureDebugAudio: Bool {
        keepDebugRecordings || diagnosticAudioRetentionPolicy != .never
    }

    func profile(for bundleIdentifier: String) -> AppProfile {
        appProfiles.first { $0.bundleIdentifier == bundleIdentifier } ?? .generic
    }

    @discardableResult
    func configureHotkeysIfNeeded() -> [HotkeyRegistrationResult] {
        let results = hotkeyCoordinator.registerHotkeys(
            dictationHotkey: dictationHotkey,
            returnHotkey: returnHotkey,
            cancelHotkey: cancelHotkey,
            onToggleDictation: { [weak self] in
                Task { await self?.toggleDictation() }
            },
            onSendReturn: { [weak self] in
                self?.sendReturn()
            },
            onCancel: { [weak self] in
                self?.interruptCurrentFlow()
            }
        )
        hotkeyStatusMessage = HotkeyRegistrationResult.message(for: results)
        return results
    }

    func startAppServicesAfterLaunch() {
        guard !didStartAppServices else { return }
        didStartAppServices = true
        configureHotkeysIfNeeded()
        startExternalTriggerIfNeeded()
        refreshPermissions()
        scheduleDeferredSherpaPrewarm(reason: "应用启动", delay: 3.0)
    }

    func startExternalTriggerIfNeeded() {
        externalTriggerService.start()
    }

    func prewarmDefaultRecognitionBackendIfNeeded() {
        startSherpaPrewarmIfEligible(respectSuppression: true)
    }

    private func startSherpaPrewarmIfEligible(respectSuppression: Bool) {
        guard recognitionBackend == .sherpaParaformer else { return }
        guard activeOperationID == nil, sessionState == .idle || sessionState == .failed || sessionState == .readyToSubmit else { return }
        if respectSuppression,
           let suppressAutomaticPrewarmUntil,
           Date() < suppressAutomaticPrewarmUntil {
            scheduleDeferredSherpaPrewarm(reason: "等待授权流程结束", delay: suppressAutomaticPrewarmUntil.timeIntervalSinceNow + 0.5)
            return
        }
        guard SherpaRuntimeLocator.findRuntimeLibrary() != nil else {
            refreshSpeechModelStatus()
            return
        }
        guard sherpaModelManager.pathsIfPresent() != nil else {
            refreshSpeechModelStatus()
            return
        }
        guard sherpaPrewarmTask == nil else { return }

        sherpaPrewarmTask = Task { [weak self] in
            guard let self else { return }
            await self.prewarmSherpaRecognizer()
        }
    }

    private func scheduleDeferredSherpaPrewarm(reason: String, delay: TimeInterval = 1.0) {
        guard recognitionBackend == .sherpaParaformer else { return }
        guard activeOperationID == nil, sessionState == .idle || sessionState == .failed || sessionState == .readyToSubmit else { return }
        deferredSherpaPrewarmTask?.cancel()
        deferredSherpaPrewarmTask = Task { [weak self] in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.deferredSherpaPrewarmTask = nil
                self.startSherpaPrewarmIfEligible(respectSuppression: true)
            }
        }
        statusMessage = "\(reason)：将在后台预热中文极速模型"
    }

    private func cancelDeferredSherpaPrewarm() {
        deferredSherpaPrewarmTask?.cancel()
        deferredSherpaPrewarmTask = nil
    }

    private func suppressAutomaticSherpaPrewarm(for seconds: TimeInterval) {
        suppressAutomaticPrewarmUntil = Date().addingTimeInterval(seconds)
        cancelDeferredSherpaPrewarm()
    }

    private func prewarmSherpaRecognizer() async {
        defer { sherpaPrewarmTask = nil }
        guard activeOperationID == nil, sessionState == .idle || sessionState == .failed || sessionState == .readyToSubmit else { return }
        do {
            speechModelState = .downloading(1)
            modelStatus = "正在预热中文极速模型"
            let state = try await withTimeout(
                seconds: 20,
                message: "中文极速模型预热超时。请重启 VoxForge 或切换识别引擎。"
            ) {
                try await self.sherpaStreamingEngine.prepare(dictionary: self.personalDictionary) { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.recognitionBackend == .sherpaParaformer else { return }
                        self.speechModelState = state
                        self.modelStatus = state.title
                    }
                }
            }
            guard recognitionBackend == .sherpaParaformer else { return }
            guard activeOperationID == nil else { return }
            speechModelState = state
            modelStatus = state.title
        } catch {
            guard recognitionBackend == .sherpaParaformer else { return }
            guard activeOperationID == nil else { return }
            speechModelState = .failed(error.localizedDescription)
            modelStatus = speechModelState.title
            errorMessage = error.localizedDescription
        }
    }

    private func configureExternalTrigger() {
        externalTriggerService.onDevicesChanged = { [weak self] devices, status in
            Task { @MainActor in
                self?.externalTriggerDevices = devices
                self?.externalTriggerStatus = status
            }
        }
        externalTriggerService.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.externalTriggerLastEvent = event
            }
        }
        externalTriggerService.onPrimaryTrigger = { [weak self] in
            Task { @MainActor in
                await self?.toggleDictation()
            }
        }
        externalTriggerService.onCancelTrigger = { [weak self] in
            Task { @MainActor in
                self?.interruptCurrentFlow()
            }
        }
    }

    func toggleDictation() async {
        switch sessionState {
        case .idle, .failed:
            await startDictation()
        case .recording:
            await finishDictation()
        case .readyToSubmit:
            sendReturn()
        case .processing, .optimizing:
            interruptCurrentFlow()
        case .inserting:
            return
        }
    }

    func startDictation() async {
        cancelDeferredSherpaPrewarm()
        let operationID = UUID()
        activeOperationID = operationID
        errorMessage = nil
        recordDiagnostic(
            category: .dictation,
            phase: "dictation.start",
            operationID: operationID,
            message: "startDictation requested"
        )
        transition(to: .processing, message: "正在检查麦克风权限")
        recordDiagnostic(category: .dictation, phase: "permission.microphone.check", operationID: operationID)
        guard await permissionCoordinator.ensureMicrophonePermission() else {
            guard isActiveOperation(operationID) else { return }
            suppressAutomaticSherpaPrewarm(for: 8)
            recordDiagnostic(
                category: .dictation,
                phase: "permission.microphone.denied",
                operationID: operationID,
                errorMessage: "microphone permission denied"
            )
            fail("需要麦克风权限才能听写。")
            return
        }
        guard isActiveOperation(operationID) else { return }
        recordDiagnostic(category: .dictation, phase: "permission.microphone.granted", operationID: operationID)

        lastTargetApplication = foregroundApplicationTracker.targetApplication()
        recordDiagnostic(
            category: .dictation,
            phase: "target_app.resolved",
            operationID: operationID,
            targetApp: lastTargetApplication,
            message: lastTargetApplication?.displayName
        )
        recordDiagnostic(
            category: .dictation,
            phase: "recognition_backend.selected",
            operationID: operationID,
            backend: recognitionBackend
        )

        switch recognitionBackend {
        case .sherpaParaformer:
            await startStreamingDictation(
                engine: sherpaStreamingEngine,
                backend: .sherpaParaformer,
                operationID: operationID,
                preparingMessage: "正在准备中文极速模型",
                recordingMessage: "正在听写：中文极速本地",
                failurePrefix: "中文极速模型启动失败"
            )
            return
        case .whisperKitStreaming:
            await startStreamingDictation(
                engine: whisperKitStreamingEngine,
                backend: .whisperKitStreaming,
                operationID: operationID,
                preparingMessage: "正在准备 WhisperKit 流式模型",
                recordingMessage: "正在听写：WhisperKit 流式",
                failurePrefix: "WhisperKit 流式模型启动失败"
            )
            return
        case .appleDictation:
            guard let appleSpeechAnalyzerEngine else {
                fail("Apple 原生听写需要 macOS 26+ SpeechAnalyzer。请切换到中文极速本地或 WhisperKit 流式。")
                return
            }
            await startStreamingDictation(
                engine: appleSpeechAnalyzerEngine,
                backend: .appleDictation,
                operationID: operationID,
                preparingMessage: "正在准备 Apple 原生听写",
                recordingMessage: "正在听写：Apple 原生听写",
                failurePrefix: "Apple 原生听写启动失败"
            )
            return
        case .whisperKit:
            break
        }

        do {
            recordDiagnostic(category: .audio, phase: "batch_audio.start_requested", operationID: operationID, backend: .whisperKit)
            try audioRecorder.startRecording()
            recordingStart = Date()
            activeDictationPath = .whisperKit
            guard isActiveOperation(operationID) else {
                _ = try? audioRecorder.stopRecording()
                return
            }
            recordDiagnostic(category: .dictation, phase: "dictation.recording_started", operationID: operationID, backend: .whisperKit)
            transition(to: .recording, message: "正在听写：WhisperKit 兼容")
        } catch {
            guard isActiveOperation(operationID) else { return }
            recordDiagnostic(category: .audio, phase: "batch_audio.start_failed", operationID: operationID, backend: .whisperKit, error: error)
            fail("无法开始录音：\(error.localizedDescription)")
        }
    }

    func finishDictation() async {
        guard sessionState == .recording else { return }
        guard let operationID = activeOperationID else { return }
        switch activeDictationPath {
        case .sherpaParaformer:
            await finishStreamingDictation(engine: sherpaStreamingEngine, operationID: operationID, finishMessage: "正在收尾中文极速识别")
        case .whisperKitStreaming:
            await finishStreamingDictation(engine: whisperKitStreamingEngine, operationID: operationID, finishMessage: "正在完成 WhisperKit 流式识别")
        case .appleDictation:
            guard let appleSpeechAnalyzerEngine else {
                fail("Apple 原生听写需要 macOS 26+ SpeechAnalyzer。")
                return
            }
            await finishStreamingDictation(engine: appleSpeechAnalyzerEngine, operationID: operationID, finishMessage: "正在完成 Apple 原生听写")
        case .whisperKit, .none:
            await finishWhisperKitDictation(operationID: operationID)
        }
    }

    private func startStreamingDictation(
        engine: StreamingSpeechEngine,
        backend: RecognitionBackend,
        operationID: UUID,
        preparingMessage: String,
        recordingMessage: String,
        failurePrefix: String
    ) async {
        scheduleStartupWatchdog(
            operationID: operationID,
            backend: backend,
            seconds: startupWatchdogTimeout(for: backend),
            failurePrefix: failurePrefix
        )
        var startupPhase = "prepare"
        do {
            transition(to: .processing, message: preparingMessage)
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.prepare.start",
                operationID: operationID,
                backend: backend,
                message: preparingMessage,
                timeoutSeconds: prepareTimeout(for: backend)
            )
            let prepareStartedAt = Date()
            let state = try await withTimeout(
                seconds: prepareTimeout(for: backend),
                message: "\(failurePrefix)：准备阶段超时。请点“刷新状态”后重试；如果仍卡住，请重启 VoxForge 或切换识别引擎。"
            ) {
                try await engine.prepare(dictionary: self.personalDictionary) { [weak self] state in
                    Task { @MainActor in
                        self?.speechModelState = state
                        self?.modelStatus = state.title
                        self?.hudController.show(state: .processing, message: state.title)
                    }
                }
            }
            guard isActiveOperation(operationID) else {
                await engine.cancel()
                return
            }
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.prepare.success",
                operationID: operationID,
                backend: backend,
                message: state.title,
                durationMs: Int(Date().timeIntervalSince(prepareStartedAt) * 1000)
            )
            speechModelState = state
            modelStatus = state.title
            activeDictationPath = ActiveDictationPath(backend: backend)
            transition(to: .processing, message: "正在创建\(backend.title)识别会话")
            startupPhase = "start_session"
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.start_session.start",
                operationID: operationID,
                backend: backend,
                message: "正在创建\(backend.title)识别会话",
                timeoutSeconds: sessionStartupTimeout(for: backend)
            )

            let sessionStartedAt = Date()
            try await withTimeout(
                seconds: sessionStartupTimeout(for: backend),
                message: "\(failurePrefix)：创建识别会话超时。通常是 sherpa runtime 或模型加载卡住，请重试或重启 VoxForge。"
            ) {
                try await engine.startSession(
                    mode: self.selectedMode,
                    language: self.transcriptionLanguage,
                    dictionary: self.personalDictionary,
                    onPartial: { [weak self] partial in
                        Task { @MainActor in
                            guard self?.isActiveOperation(operationID) == true else { return }
                            if self?.lastTranscript.isEmpty == true {
                                self?.recordDiagnostic(
                                    category: .recognition,
                                    phase: "recognition.first_partial",
                                    operationID: operationID,
                                    backend: backend
                                )
                            }
                            self?.lastTranscript = partial
                            self?.hudController.show(state: .recording, message: "正在听写：实时识别中", preview: partial)
                        }
                    }
                )
            }
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.start_session.success",
                operationID: operationID,
                backend: backend,
                durationMs: Int(Date().timeIntervalSince(sessionStartedAt) * 1000)
            )

            startupPhase = "audio_start"
            transition(to: .processing, message: "正在启动麦克风输入")
            recordDiagnostic(
                category: .audio,
                phase: "streaming_audio.start.begin",
                operationID: operationID,
                backend: backend,
                message: "正在启动麦克风输入"
            )
            lastAudioBufferOperationID = nil
            var streamContinuation: AsyncStream<AudioBuffer>.Continuation?
            let audioStream = AsyncStream<AudioBuffer> { continuation in
                streamContinuation = continuation
            }
            audioBufferContinuation = streamContinuation
            audioBufferConsumerTask = Task { [weak self] in
                var didReceiveFirstBuffer = false
                for await buffer in audioStream {
                    if !didReceiveFirstBuffer {
                        didReceiveFirstBuffer = true
                        await MainActor.run {
                            guard self?.isActiveOperation(operationID) == true else { return }
                            self?.lastAudioBufferOperationID = operationID
                            self?.cancelAudioStartupWatchdog()
                        }
                    }
                    await engine.acceptAudio(samples: buffer.samples, sampleRate: buffer.sampleRate)
                }
            }
            let audioContinuation = streamContinuation
            try streamingAudioRecorder.startStreaming(keepDebugFile: shouldCaptureDebugAudio) { samples, sampleRate in
                audioContinuation?.yield(AudioBuffer(samples: samples, sampleRate: sampleRate))
            } onStreamInterrupted: { error in
                Task { @MainActor in
                    guard self.isActiveOperation(operationID),
                          self.activeDictationPath == ActiveDictationPath(backend: backend)
                    else { return }
                    self.recordDiagnostic(
                        category: .audio,
                        phase: "streaming_audio.interrupted",
                        operationID: operationID,
                        backend: backend,
                        error: error
                    )
                    _ = try? self.streamingAudioRecorder.stopStreaming()
                    self.cancelAudioStartupWatchdog()
                    self.cancelAudioBufferForwarding()
                    await engine.cancel()
                    self.activeDictationPath = nil
                    self.rebuildStreamingEngine(for: backend)
                    self.fail("音频输入设备已变化，听写已停止，请重试。")
                }
            }
            guard isActiveOperation(operationID) else {
                _ = try? streamingAudioRecorder.stopStreaming()
                cancelAudioBufferForwarding()
                await engine.cancel()
                return
            }
            recordingStart = Date()
            cancelStartupWatchdog()
            scheduleAudioStartupWatchdog(operationID: operationID, backend: backend, engine: engine, seconds: 2.0)
            recordDiagnostic(
                category: .dictation,
                phase: "dictation.recording_started",
                operationID: operationID,
                backend: backend
            )
            transition(to: .recording, message: recordingMessage)
        } catch {
            guard isActiveOperation(operationID) else { return }
            cancelStartupWatchdog()
            cancelAudioStartupWatchdog()
            let timedOut = (error as? TypeMoreError)?.isOperationTimeout == true
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.\(startupPhase).failed",
                operationID: operationID,
                backend: backend,
                error: error,
                timeoutSeconds: timedOut ? (startupPhase == "prepare" ? prepareTimeout(for: backend) : sessionStartupTimeout(for: backend)) : nil,
                details: [
                    "willCancelEngine": "true",
                    "willRebuildEngine": String(backend.isStreaming)
                ]
            )
            cancelEngineAfterStartupFailure(engine, error: error)
            activeDictationPath = nil
            rebuildStreamingEngine(for: backend)
            speechModelState = .failed(error.localizedDescription)
            modelStatus = speechModelState.title
            fail("\(error.localizedDescription)。当前设置为 \(backend.title)，不会自动切换其他识别引擎。")
        }
    }

    private func finishStreamingDictation(engine: StreamingSpeechEngine, operationID: UUID, finishMessage: String) async {
        cancelAudioStartupWatchdog()
        transition(to: .processing, message: finishMessage, preview: lastTranscript)
        recordDiagnostic(
            category: .dictation,
            phase: "dictation.finish.start",
            operationID: operationID,
            message: finishMessage
        )

        do {
            let recording = try streamingAudioRecorder.stopStreaming()
            await finishAudioBufferForwarding()
            recordDiagnostic(
                category: .audio,
                phase: "streaming_audio.summary",
                operationID: operationID,
                durationMs: Int(recording.duration * 1000),
                samplesRecorded: recording.samplesRecorded,
                debugAudioURL: recording.fileURL
            )
            let result = try await engine.finish(recording: recording)
            guard isActiveOperation(operationID) else {
                await engine.cancel()
                return
            }
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.finish.success",
                operationID: operationID,
                backend: result.backend,
                durationMs: Int(result.finalizationLatency * 1000),
                samplesRecorded: recording.samplesRecorded,
                debugAudioURL: result.debugAudioURL,
                details: ["realTimeFactor": String(format: "%.2f", result.realTimeFactor)]
            )
            activeDictationPath = nil
            modelStatus = performanceStatus(for: result)
            try await completeDictation(
                rawTranscript: result.text,
                duration: result.duration,
                debugAudioURL: result.debugAudioURL,
                backend: result.backend,
                operationID: operationID
            )
        } catch {
            guard isActiveOperation(operationID) else { return }
            cancelAudioBufferForwarding()
            let failedPath = activeDictationPath
            activeDictationPath = nil
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.finish.failed",
                operationID: operationID,
                error: error,
                details: [
                    "willCancelEngine": "true",
                    "willRebuildEngine": String(failedPath != nil)
                ]
            )
            await engine.cancel()
            if let failedPath {
                rebuildStreamingEngine(for: failedPath.backend)
            }
            fail("听写失败：\(error.localizedDescription)")
        }
    }

    private func finishWhisperKitDictation(operationID: UUID) async {
        transition(to: .processing, message: "正在用 WhisperKit 本地转写")
        recordDiagnostic(category: .dictation, phase: "dictation.finish.start", operationID: operationID, backend: .whisperKit, message: "正在用 WhisperKit 本地转写")

        do {
            let audio = try audioRecorder.stopRecording()
            recordDiagnostic(
                category: .audio,
                phase: "batch_audio.summary",
                operationID: operationID,
                backend: .whisperKit,
                durationMs: Int(audio.duration * 1000),
                samplesRecorded: audio.samplesRecorded,
                debugAudioURL: audio.fileURL
            )
            let rawTranscript = try await transcriptionEngine.transcribe(
                audio: audio,
                mode: selectedMode,
                language: transcriptionLanguage
            )
            guard isActiveOperation(operationID) else { return }
            activeDictationPath = nil
            try await completeDictation(
                rawTranscript: rawTranscript,
                duration: audio.duration,
                debugAudioURL: audio.fileURL,
                backend: .whisperKit,
                operationID: operationID
            )
            cleanupRecordingIfNeeded(audio.fileURL)
        } catch {
            guard isActiveOperation(operationID) else { return }
            activeDictationPath = nil
            recordDiagnostic(category: .recognition, phase: "recognition.finish.failed", operationID: operationID, backend: .whisperKit, error: error)
            fail("听写失败：\(error.localizedDescription)")
        }
    }

    private func completeDictation(rawTranscript: String, duration: TimeInterval, debugAudioURL: URL?, backend: RecognitionBackend, operationID: UUID) async throws {
        guard isActiveOperation(operationID) else { return }
        recordDiagnostic(
            category: .dictation,
            phase: "dictation.postprocess.start",
            operationID: operationID,
            backend: backend,
            durationMs: Int(duration * 1000),
            debugAudioURL: debugAudioURL
        )
        let targetApp = lastTargetApplication ?? RunningApplicationInfo.frontmost()
        let profile = profile(for: targetApp.bundleIdentifier)
        let processed = postProcessor.process(
            rawTranscript,
            mode: selectedMode,
            profile: profile,
            dictionary: personalDictionary
        )
        var finalText = processed
        var optimizedWithLLM = false

        if llmOptimizationEnabled {
            loadLLMAPIKeyIfNeeded()
            recordDiagnostic(
                category: .dictation,
                phase: "llm.optimize.start",
                operationID: operationID,
                backend: backend,
                targetApp: targetApp,
                details: [
                    "baseURL": llmBaseURL,
                    "model": llmModel,
                    "hasAPIKey": llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                    "usesDefaultPrompt": isUsingDefaultLLMPromptTemplate(for: selectedMode) ? "true" : "false"
                ]
            )
            transition(to: .optimizing, message: "正在用大模型优化", preview: processed)
            do {
                finalText = try await llmOptimizationService.optimize(
                    text: processed,
                    rawText: rawTranscript,
                    mode: selectedMode,
                    profile: profile,
                    configuration: llmConfiguration
                )
                guard isActiveOperation(operationID) else { return }
                optimizedWithLLM = true
                recordDiagnostic(
                    category: .dictation,
                    phase: "llm.optimize.success",
                    operationID: operationID,
                    backend: backend,
                    targetApp: targetApp
                )
            } catch {
                guard isActiveOperation(operationID) else { return }
                recordDiagnostic(category: .dictation, phase: "llm.optimize.failed", operationID: operationID, backend: backend, error: error)
                statusMessage = "大模型优化失败，已使用本地结果：\(error.localizedDescription)"
                hudController.show(state: .optimizing, message: "大模型优化失败，已使用本地结果", preview: processed)
            }
        } else {
            recordDiagnostic(
                category: .dictation,
                phase: "llm.optimize.skipped",
                operationID: operationID,
                backend: backend,
                targetApp: targetApp,
                message: "大模型优化未启用"
            )
        }

        lastTranscript = finalText
        recordDiagnostic(
            category: .dictation,
            phase: "dictation.postprocess.success",
            operationID: operationID,
            backend: backend,
            targetApp: targetApp,
            debugAudioURL: debugAudioURL
        )

        if targetApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            saveTranscript(finalText, rawTranscript: rawTranscript, duration: duration, targetApp: targetApp, inserted: false, optimizedWithLLM: optimizedWithLLM)
            cleanupDebugAudioIfNeeded(debugAudioURL)
            activeOperationID = nil
            transition(to: .idle, message: "已生成文本。目标是 VoxForge 自身，因此未自动输入。", preview: finalText)
            hudController.showCompletion(message: "已生成文本", preview: finalText)
            return
        }

        guard await ensureAccessibilityForInput(action: "把文本输入到当前应用") else {
            guard isActiveOperation(operationID) else { return }
            saveTranscript(finalText, rawTranscript: rawTranscript, duration: duration, targetApp: targetApp, inserted: false, optimizedWithLLM: optimizedWithLLM)
            cleanupDebugAudioIfNeeded(debugAudioURL)
            return
        }
        guard isActiveOperation(operationID) else { return }

        hudController.hide()
        transition(to: .inserting, message: "正在输入到 \(targetApp.displayName)", preview: finalText)
        do {
            try await textInsertionService.insert(finalText, targetBundleIdentifier: targetApp.bundleIdentifier)
        } catch TypeMoreError.targetActivationFailed {
            guard isActiveOperation(operationID) else { return }
            saveTranscript(finalText, rawTranscript: rawTranscript, duration: duration, targetApp: targetApp, inserted: false, optimizedWithLLM: optimizedWithLLM)
            cleanupDebugAudioIfNeeded(debugAudioURL)
            activeOperationID = nil
            transition(to: .failed, message: "目标应用未能激活，文本已保留在剪贴板。", preview: finalText)
            hudController.showCompletion(message: "目标应用未能激活，文本已在剪贴板", preview: finalText)
            return
        }
        guard isActiveOperation(operationID) else { return }
        saveTranscript(finalText, rawTranscript: rawTranscript, duration: duration, targetApp: targetApp, inserted: true, optimizedWithLLM: optimizedWithLLM)
        cleanupDebugAudioIfNeeded(debugAudioURL)

        transition(to: .readyToSubmit, message: "已输入到 \(targetApp.displayName)。再次按听写快捷键发送回车。", preview: finalText)
        hudController.showReadyToSubmit(message: "已输入到 \(targetApp.displayName)，再按一次发送回车")
    }

    func cancelDictation() {
        interruptCurrentFlow()
    }

    func interruptCurrentFlow() {
        guard sessionState != .idle else {
            hudController.hide()
            return
        }
        guard sessionState != .inserting else { return }
        recordDiagnostic(
            category: .dictation,
            phase: "dictation.interrupt",
            operationID: activeOperationID,
            message: "user interrupt"
        )
        cancelStartupWatchdog()
        cancelAudioStartupWatchdog()
        cancelAudioBufferForwarding()
        activeOperationID = nil
        if activeDictationPath == .sherpaParaformer {
            _ = try? streamingAudioRecorder.stopStreaming()
            Task { await sherpaStreamingEngine.cancel() }
            rebuildSherpaStreamingEngine()
        } else if activeDictationPath == .whisperKitStreaming {
            _ = try? streamingAudioRecorder.stopStreaming()
            Task { await whisperKitStreamingEngine.cancel() }
        } else if activeDictationPath == .appleDictation {
            _ = try? streamingAudioRecorder.stopStreaming()
            if let appleSpeechAnalyzerEngine {
                Task { await appleSpeechAnalyzerEngine.cancel() }
            }
        } else if sessionState == .recording {
            _ = try? audioRecorder.stopRecording()
        }
        activeDictationPath = nil
        transition(to: .idle, message: "已取消听写")
        hudController.showCompletion(message: "已中断")
    }

    func sendReturn() {
        Task {
            guard await ensureAccessibilityForInput(action: "发送回车") else { return }
            let targetApp = resolvedReturnTargetApplication()

            do {
                try await textInsertionService.sendReturn(targetBundleIdentifier: targetApp.bundleIdentifier)
                activeOperationID = nil
                lastTargetApplication = nil
                let message = targetApp.bundleIdentifier == RunningApplicationInfo.generic.bundleIdentifier
                    ? "已发送回车"
                    : "已向 \(targetApp.displayName) 发送回车"
                transition(to: .idle, message: message)
            } catch {
                fail("无法发送回车：\(error.localizedDescription)")
            }
        }
    }

    private func resolvedReturnTargetApplication() -> RunningApplicationInfo {
        if let lastTargetApplication,
           lastTargetApplication.bundleIdentifier != Bundle.main.bundleIdentifier,
           lastTargetApplication.bundleIdentifier != RunningApplicationInfo.generic.bundleIdentifier {
            return lastTargetApplication
        }
        return foregroundApplicationTracker.targetApplication()
    }

    private func ensureAccessibilityForInput(action: String) async -> Bool {
        refreshPermissions()
        if accessibilityPermissionGranted {
            return true
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        refreshPermissions()
        if accessibilityPermissionGranted {
            return true
        }

        suppressAutomaticSherpaPrewarm(for: 12)
        permissionCoordinator.openAccessibilityPrompt()
        fail(accessibilityHelpMessage(action: action))
        return false
    }

    private func isActiveOperation(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
    }

    private func recordDiagnostic(
        category: DiagnosticEvent.Category,
        phase: String,
        operationID: UUID? = nil,
        backend: RecognitionBackend? = nil,
        targetApp: RunningApplicationInfo? = nil,
        message: String? = nil,
        error: Error? = nil,
        errorMessage: String? = nil,
        timeoutSeconds: TimeInterval? = nil,
        durationMs: Int? = nil,
        samplesRecorded: Int? = nil,
        debugAudioURL: URL? = nil,
        details: [String: String] = [:]
    ) {
        let event = DiagnosticEvent(
            category: category,
            phase: phase,
            operationID: operationID?.uuidString,
            backend: backend?.title ?? recognitionBackend.title,
            mode: selectedMode.title,
            language: transcriptionLanguage.title,
            targetAppName: targetApp?.displayName ?? lastTargetApplication?.displayName,
            targetBundleIdentifier: targetApp?.bundleIdentifier ?? lastTargetApplication?.bundleIdentifier,
            sessionState: sessionState.rawValue,
            activeDictationPath: activeDictationPath?.diagnosticName,
            message: message,
            error: errorMessage ?? error?.localizedDescription,
            durationMs: durationMs,
            timeoutSeconds: timeoutSeconds,
            samplesRecorded: samplesRecorded,
            debugAudioPath: debugAudioURL?.path,
            details: details
        )
        diagnosticsRecorder.record(event)
        if let summary = event.failureSummary {
            recentDiagnosticFailureSummary = summary
        }
    }

    private func prepareTimeout(for backend: RecognitionBackend) -> TimeInterval {
        switch backend {
        case .sherpaParaformer:
            return sherpaModelManager.pathsIfPresent() == nil ? 180 : 20
        case .whisperKitStreaming:
            return 180
        case .appleDictation:
            return 90
        case .whisperKit:
            return 60
        }
    }

    private func sessionStartupTimeout(for backend: RecognitionBackend) -> TimeInterval {
        switch backend {
        case .sherpaParaformer:
            return 20
        case .whisperKitStreaming, .appleDictation:
            return 30
        case .whisperKit:
            return 20
        }
    }

    private func startupWatchdogTimeout(for backend: RecognitionBackend) -> TimeInterval {
        prepareTimeout(for: backend) + sessionStartupTimeout(for: backend) + 5
    }

    private func scheduleStartupWatchdog(
        operationID: UUID,
        backend: RecognitionBackend,
        seconds: TimeInterval,
        failurePrefix: String
    ) {
        cancelStartupWatchdog()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.isActiveOperation(operationID),
                      self.sessionState == .processing
                else { return }

                if backend == .sherpaParaformer {
                    self.recordDiagnostic(
                        category: .recognition,
                        phase: "recognition.startup_watchdog.rebuild_sherpa",
                        operationID: operationID,
                        backend: backend,
                        timeoutSeconds: seconds,
                        details: [
                            "willCancelEngine": "false",
                            "willRebuildSherpa": "true"
                        ]
                    )
                    self.rebuildSherpaStreamingEngine()
                }
                self.activeDictationPath = nil
                self.speechModelState = .failed("启动超时")
                self.modelStatus = self.speechModelState.title
                self.recordDiagnostic(
                    category: .recognition,
                    phase: "recognition.startup_watchdog.timeout",
                    operationID: operationID,
                    backend: backend,
                    errorMessage: "\(failurePrefix)：启动超过 \(Int(seconds)) 秒仍未完成。",
                    timeoutSeconds: seconds,
                    details: [
                        "willCancelEngine": "false",
                        "willRebuildSherpa": String(backend == .sherpaParaformer)
                    ]
                )
                self.fail("\(failurePrefix)：启动超过 \(Int(seconds)) 秒仍未完成。已重置中文极速引擎，请重试；如果仍频繁发生，请重启 VoxForge 或切换识别引擎。")
            }
        }
        startupWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelStartupWatchdog() {
        startupWatchdog?.cancel()
        startupWatchdog = nil
    }

    private func scheduleAudioStartupWatchdog(
        operationID: UUID,
        backend: RecognitionBackend,
        engine: StreamingSpeechEngine,
        seconds: TimeInterval
    ) {
        cancelAudioStartupWatchdog()
        guard lastAudioBufferOperationID != operationID else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.isActiveOperation(operationID),
                      self.activeDictationPath == ActiveDictationPath(backend: backend),
                      self.lastAudioBufferOperationID != operationID
                else { return }

                self.recordDiagnostic(
                    category: .audio,
                    phase: "streaming_audio.first_buffer.timeout",
                    operationID: operationID,
                    backend: backend,
                    errorMessage: "麦克风输入启动后 \(String(format: "%.1f", seconds)) 秒内没有收到音频数据。",
                    timeoutSeconds: seconds,
                    details: [
                        "willCancelEngine": "true",
                        "willRebuildSherpa": String(backend == .sherpaParaformer)
                    ]
                )
                _ = try? self.streamingAudioRecorder.stopStreaming()
                await engine.cancel()
                self.activeDictationPath = nil
                if backend == .sherpaParaformer {
                    self.rebuildSherpaStreamingEngine()
                }
                self.fail("麦克风输入没有返回音频数据。请检查或重新连接当前输入设备后重试。")
            }
        }
        audioStartupWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelAudioStartupWatchdog() {
        audioStartupWatchdog?.cancel()
        audioStartupWatchdog = nil
    }

    private func finishAudioBufferForwarding() async {
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        await audioBufferConsumerTask?.value
        audioBufferConsumerTask = nil
    }

    private func cancelAudioBufferForwarding() {
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioBufferConsumerTask?.cancel()
        audioBufferConsumerTask = nil
    }

    private func cancelEngineAfterStartupFailure(_ engine: StreamingSpeechEngine, error: Error) {
        recordDiagnostic(
            category: .recognition,
            phase: "recognition.engine_cancel.requested",
            operationID: activeOperationID,
            error: error
        )
        Task { await engine.cancel() }
    }

    private func rebuildSherpaStreamingEngine() {
        recordDiagnostic(
            category: .recognition,
            phase: "recognition.sherpa_engine.rebuild",
            operationID: activeOperationID,
            backend: .sherpaParaformer
        )
        sherpaStreamingEngine = SherpaParaformerStreamingEngine(modelManager: sherpaModelManager)
    }

    private func rebuildStreamingEngine(for backend: RecognitionBackend) {
        switch backend {
        case .sherpaParaformer:
            rebuildSherpaStreamingEngine()
        case .whisperKitStreaming:
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.whisperkit_streaming_engine.rebuild",
                operationID: activeOperationID,
                backend: .whisperKitStreaming
            )
            whisperKitStreamingEngine = WhisperKitStreamingEngine(modelName: whisperKitStreamingModel)
        case .appleDictation:
            recordDiagnostic(
                category: .recognition,
                phase: "recognition.apple_speech_engine.rebuild",
                operationID: activeOperationID,
                backend: .appleDictation
            )
            if #available(macOS 26.0, *) {
                appleSpeechAnalyzerEngine = AppleSpeechAnalyzerStreamingEngine()
            } else {
                appleSpeechAnalyzerEngine = nil
            }
        case .whisperKit:
            break
        }
    }

    private func accessibilityHelpMessage(action: String) -> String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix("/.build/debug/TypeMore") {
            return "需要辅助功能权限才能\(action)。当前运行的是 SwiftPM 调试可执行文件：\(bundlePath)。请在系统设置里授权这个可执行文件，或用打包后的 VoxForge.app 启动。"
        }

        if bundlePath.contains("/dist/") {
            return "需要辅助功能权限才能\(action)。当前运行的是：\(bundlePath)。如果系统设置里已经打开 VoxForge 声铸仍失败，请先关闭再打开该开关；仍不生效时删除旧项后重新添加这个 dist 里的应用，并重启 VoxForge。"
        }

        return "需要辅助功能权限才能\(action)。当前运行的是：\(bundlePath)。如果系统设置里已经打开 VoxForge 声铸仍失败，请关闭再打开该开关，或删除后重新添加当前这个应用。"
    }

    func requestAccessibility() {
        suppressAutomaticSherpaPrewarm(for: 12)
        permissionCoordinator.openAccessibilityPrompt()
        refreshPermissions()
        if !accessibilityPermissionGranted {
            statusMessage = "请在系统设置中允许 VoxForge 声铸使用辅助功能，授权后回到应用会自动刷新。"
        }
    }

    func refreshPermissions() {
        accessibilityPermissionGranted = permissionCoordinator.hasAccessibilityPermission
        guard accessibilityPermissionGranted else { return }

        if errorMessage?.contains("辅助功能权限") == true {
            errorMessage = nil
            if sessionState == .failed {
                sessionState = .idle
                hudController.hide()
            }
            statusMessage = "辅助功能权限已开启，可以开始听写。"
            scheduleDeferredSherpaPrewarm(reason: "辅助功能权限已开启", delay: 1.5)
        }
    }

    func clearHistory() {
        transcriptRecords = []
        historyStore.save([], retention: historyRetention)
        statusMessage = "历史记录已清空"
    }

    func addDictionaryEntry() {
        personalDictionary.append(DictionaryEntry(term: ""))
        statusMessage = "已新增词典词条"
    }

    func updateDictionaryEntry(_ entry: DictionaryEntry) {
        guard let index = personalDictionary.firstIndex(where: { $0.id == entry.id }) else { return }
        personalDictionary[index] = entry
        persistPersonalDictionary()
    }

    func deleteDictionaryEntry(_ entry: DictionaryEntry) {
        personalDictionary.removeAll { $0.id == entry.id }
        persistPersonalDictionary()
        statusMessage = "词典词条已删除"
    }

    func resetPersonalDictionary() {
        settingsStore.resetPersonalDictionary()
        personalDictionary = settingsStore.personalDictionary
        statusMessage = "词典已恢复默认"
    }

    func updateHotkey(_ target: HotkeyTarget, to hotkey: HotkeyDefinition) {
        let oldDictationHotkey = dictationHotkey
        let oldReturnHotkey = returnHotkey
        let oldCancelHotkey = cancelHotkey

        switch target {
        case .dictation:
            dictationHotkey = hotkey
        case .returnKey:
            returnHotkey = hotkey
        case .cancel:
            cancelHotkey = hotkey
        }
        let results = configureHotkeysIfNeeded()
        let targetResult = results.first { $0.target == target }
        guard targetResult?.succeeded ?? true else {
            dictationHotkey = oldDictationHotkey
            returnHotkey = oldReturnHotkey
            cancelHotkey = oldCancelHotkey
            _ = configureHotkeysIfNeeded()
            hotkeyStatusMessage = "快捷键注册失败，已保留原设置：\(HotkeyRegistrationResult.message(for: results))"
            return
        }

        switch target {
        case .dictation:
            settingsStore.dictationHotkey = hotkey
        case .returnKey:
            settingsStore.returnHotkey = hotkey
        case .cancel:
            settingsStore.cancelHotkey = hotkey
        }
    }

    func updateSelectedMode(_ mode: DictationMode) {
        selectedMode = mode
        settingsStore.selectedMode = mode
    }

    func updateTranscriptionLanguage(_ language: TranscriptionLanguage) {
        transcriptionLanguage = language
        settingsStore.transcriptionLanguage = language
    }

    func updateRecognitionBackend(_ backend: RecognitionBackend) {
        recognitionBackend = backend
        settingsStore.recognitionBackend = backend
        updateRecognitionBackendStatus(backend)
        errorMessage = nil
        scheduleDeferredSherpaPrewarm(reason: "识别引擎已切换", delay: 1.0)
    }

    private func updateRecognitionBackendStatus(_ backend: RecognitionBackend) {
        switch backend {
        case .sherpaParaformer:
            modelStatus = speechModelState.title
        case .whisperKitStreaming:
            modelStatus = "WhisperKit 流式模型：\(whisperKitStreamingModel)"
        case .whisperKit:
            modelStatus = "WhisperKit batch 兼容"
        case .appleDictation:
            modelStatus = RecognitionBackend.isAppleDictationSupported
                ? "Apple 原生听写可用（实验）"
                : "Apple 原生听写需要 macOS 26+"
        }
    }

    func refreshSpeechModelStatus() {
        if SherpaRuntimeLocator.findRuntimeLibrary() == nil {
            speechModelState = .missingRuntime
        } else {
            speechModelState = sherpaModelManager.status()
        }
        if recognitionBackend == .sherpaParaformer {
            modelStatus = speechModelState.title
        }
    }

    func updateWhisperKitStreamingModel(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        whisperKitStreamingModel = trimmed
        settingsStore.whisperKitStreamingModel = trimmed
        if recognitionBackend == .whisperKitStreaming {
            modelStatus = "WhisperKit 流式模型：\(trimmed)。重启应用后加载新模型。"
        }
    }

    func downloadSherpaModel() async {
        do {
            _ = try await sherpaModelManager.ensureModel { [weak self] state in
                Task { @MainActor in
                    self?.speechModelState = state
                    self?.modelStatus = state.title
                }
            }
            refreshSpeechModelStatus()
        } catch {
            speechModelState = .failed(error.localizedDescription)
            modelStatus = speechModelState.title
            errorMessage = error.localizedDescription
        }
    }

    func updateSaveHistory(_ enabled: Bool) {
        saveHistory = enabled
        settingsStore.saveHistory = enabled
    }

    func updateHistoryRetention(_ retention: HistoryRetention) {
        historyRetention = retention
        settingsStore.historyRetention = retention
        transcriptRecords = historyStore.load(retention: retention)
        historyStore.save(transcriptRecords, retention: retention)
    }

    func updateLLMOptimizationEnabled(_ enabled: Bool) {
        llmOptimizationEnabled = enabled
        settingsStore.llmOptimizationEnabled = enabled
    }

    func loadLLMAPIKeyIfNeeded() {
        guard !hasLoadedLLMAPIKey else { return }
        llmAPIKey = keychainStore.string(for: "llmAPIKey")
        hasLoadedLLMAPIKey = true
    }

    func updateLLMBaseURL(_ value: String) {
        llmBaseURL = value
        settingsStore.llmBaseURL = value
    }

    func updateLLMModel(_ value: String) {
        llmModel = value
        settingsStore.llmModel = value
    }

    func updateLLMStyleInstruction(_ value: String) {
        llmStyleInstruction = value
        settingsStore.llmStyleInstruction = value
    }

    func updateLLMCustomPrompt(_ value: String) {
        llmCustomPrompt = value
        settingsStore.llmCustomPrompt = value
    }

    func llmPromptTemplate(for mode: DictationMode) -> String {
        let customTemplate = settingsStore.llmPromptTemplate(for: mode)
        if customTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return OpenAICompatibleOptimizationService.defaultPromptTemplate(for: mode)
        }
        return customTemplate
    }

    func isUsingDefaultLLMPromptTemplate(for mode: DictationMode) -> Bool {
        settingsStore.llmPromptTemplate(for: mode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func updateLLMPromptTemplateMode(_ mode: DictationMode) {
        llmPromptTemplateMode = mode
    }

    func updateLLMPromptTemplate(_ value: String, for mode: DictationMode) {
        settingsStore.setLLMPromptTemplate(value, for: mode)
        if mode == .codingPrompt {
            llmCustomPrompt = value
        }
    }

    func resetLLMPromptTemplate(for mode: DictationMode) {
        settingsStore.resetLLMPromptTemplate(for: mode)
        if mode == .codingPrompt {
            llmCustomPrompt = ""
        }
    }

    func resetAllLLMPromptTemplates() {
        settingsStore.resetAllLLMPromptTemplates()
        llmCustomPrompt = ""
    }

    func updateLLMAPIKey(_ value: String) {
        llmAPIKey = value
        hasLoadedLLMAPIKey = true
        keychainStore.setString(value, for: "llmAPIKey")
    }

    func updateKeepDebugRecordings(_ enabled: Bool) {
        keepDebugRecordings = enabled
        settingsStore.keepDebugRecordings = enabled
    }

    func updateDiagnosticAudioRetentionPolicy(_ policy: DiagnosticAudioRetentionPolicy) {
        diagnosticAudioRetentionPolicy = policy
        settingsStore.diagnosticAudioRetentionPolicy = policy
    }

    func exportDiagnosticsPackage() {
        let audioURLs = diagnosticAudioURLsForExport()
        let environment = DiagnosticEnvironment(
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            recognitionBackend: recognitionBackend.title,
            mode: selectedMode.title,
            language: transcriptionLanguage.title,
            modelStatus: modelStatus,
            keepDebugRecordings: keepDebugRecordings,
            audioRetentionPolicy: diagnosticAudioRetentionPolicy.rawValue,
            recentFailure: diagnosticsRecorder.recentFailureSummary()
        )

        do {
            let result = try diagnosticPackageExporter.exportPackage(environment: environment, audioFileURLs: audioURLs)
            lastDiagnosticPackageURL = result.packageURL
            diagnosticStatusMessage = "已导出诊断包：\(result.packageURL.path)（音频 \(result.includedAudioFiles) 个）"
            recordDiagnostic(category: .diagnostics, phase: "diagnostics.export.success", message: result.packageURL.path)
        } catch {
            diagnosticStatusMessage = "导出诊断包失败：\(error.localizedDescription)"
            recordDiagnostic(category: .diagnostics, phase: "diagnostics.export.failed", error: error)
        }
    }

    func clearDiagnostics() {
        do {
            try diagnosticsRecorder.clear()
            recentDiagnosticFailureSummary = nil
            lastDiagnosticPackageURL = nil
            diagnosticStatusMessage = "诊断日志已清空"
        } catch {
            diagnosticStatusMessage = "清空诊断日志失败：\(error.localizedDescription)"
        }
    }

    func updateExternalTriggerEnabled(_ enabled: Bool) {
        externalTriggerEnabled = enabled
        settingsStore.externalTriggerEnabled = enabled
        updateExternalTriggerConfiguration()
    }

    func updateExternalTriggerSuppressVolume(_ enabled: Bool) {
        externalTriggerSuppressVolume = enabled
        settingsStore.externalTriggerSuppressVolume = enabled
        updateExternalTriggerConfiguration()
    }

    func updateExternalTriggerCancelModifier(_ modifier: ExternalTriggerCancelModifier) {
        externalTriggerCancelModifier = modifier
        settingsStore.externalTriggerCancelModifier = modifier
        updateExternalTriggerConfiguration()
    }

    func selectExternalTriggerDevice(_ device: ExternalTriggerDevice) {
        guard let vendorID = device.vendorID, let productID = device.productID else { return }
        externalTriggerVendorID = vendorID
        externalTriggerProductID = productID
        settingsStore.externalTriggerVendorID = vendorID
        settingsStore.externalTriggerProductID = productID
        updateExternalTriggerConfiguration()
    }

    func recheckExternalTrigger() {
        externalTriggerService.recheck()
    }

    func testExternalTriggerButton() {
        externalTriggerLastEvent = ExternalTriggerLastEvent(type: .singleClick, date: Date(), suppressed: false)
        statusMessage = "请按下 DJI Mic 按钮，最近事件会显示在设置页。"
    }

    private func updateExternalTriggerConfiguration() {
        externalTriggerService.update(configuration: ExternalTriggerService.Configuration(
            enabled: externalTriggerEnabled,
            vendorID: externalTriggerVendorID,
            productID: externalTriggerProductID,
            suppressVolume: externalTriggerSuppressVolume,
            cancelModifier: externalTriggerCancelModifier
        ))
    }

    private func persistPersonalDictionary() {
        settingsStore.personalDictionary = personalDictionary
        let sanitized = SettingsStore.sanitizedDictionary(personalDictionary)
        let draftEntries = personalDictionary.filter {
            $0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        personalDictionary = sanitized + draftEntries
    }

    var llmConfiguration: LLMOptimizationConfiguration {
        LLMOptimizationConfiguration(
            isEnabled: llmOptimizationEnabled,
            baseURL: llmBaseURL,
            apiKey: llmAPIKey,
            model: llmModel,
            styleInstruction: llmStyleInstruction,
            customPrompt: settingsStore.llmPromptTemplate(for: selectedMode),
            dictionaryContext: OpenAICompatibleOptimizationService.dictionaryContext(from: personalDictionary)
        )
    }

    private func saveTranscript(_ text: String, rawTranscript: String, duration: TimeInterval, targetApp: RunningApplicationInfo, inserted: Bool, optimizedWithLLM: Bool) {
        guard saveHistory else { return }
        let record = TranscriptRecord(
            text: text,
            rawText: rawTranscript,
            mode: selectedMode,
            targetApplicationName: targetApp.displayName,
            targetBundleIdentifier: targetApp.bundleIdentifier,
            duration: duration,
            inserted: inserted,
            optimizedWithLLM: optimizedWithLLM
        )
        transcriptRecords.insert(record, at: 0)
        transcriptRecords = Array(transcriptRecords.filter { record in
            historyRetention.cutoffDate.map { record.createdAt >= $0 } ?? true
        }.prefix(200))
        historyStore.save(transcriptRecords, retention: historyRetention)
    }

    private func transition(to state: DictationSessionState, message: String, preview: String? = nil) {
        sessionState = state
        statusMessage = message
        recordDiagnostic(
            category: .dictation,
            phase: "state.transition",
            operationID: activeOperationID,
            message: message,
            details: ["newState": state.rawValue]
        )
        if state == .idle || state == .readyToSubmit || state == .inserting {
            return
        }
        hudController.show(state: state, message: message, preview: preview)
    }

    private func cleanupRecordingIfNeeded(_ audioURL: URL) {
        guard !keepDebugRecordings, diagnosticAudioRetentionPolicy != .always else { return }
        try? FileManager.default.removeItem(at: audioURL)
    }

    private func cleanupDebugAudioIfNeeded(_ audioURL: URL?) {
        guard let audioURL, !keepDebugRecordings, diagnosticAudioRetentionPolicy != .always else { return }
        try? FileManager.default.removeItem(at: audioURL)
    }

    private func diagnosticAudioURLsForExport() -> [URL] {
        guard let path = diagnosticsRecorder.recentFailureSummary()?.debugAudioPath else {
            return []
        }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }

    private func performanceStatus(for result: StreamingTranscriptionResult) -> String {
        let firstPartial = result.firstPartialLatency.map { String(format: "%.2fs 首字", $0) } ?? "无首字"
        let final = String(format: "%.2fs 收尾", result.finalizationLatency)
        let rtf = String(format: "RTF %.2f", result.realTimeFactor)
        return "\(result.backend.title) 已就绪 · \(firstPartial) · \(final) · \(rtf)"
    }

    private func fail(_ message: String) {
        recordDiagnostic(
            category: .dictation,
            phase: "dictation.fail",
            operationID: activeOperationID,
            errorMessage: message
        )
        activeOperationID = nil
        sessionState = .failed
        errorMessage = message
        statusMessage = message
        hudController.showFailure(message: message)
    }
}

private enum ActiveDictationPath: Equatable {
    case sherpaParaformer
    case whisperKitStreaming
    case appleDictation
    case whisperKit

    init(backend: RecognitionBackend) {
        switch backend {
        case .sherpaParaformer:
            self = .sherpaParaformer
        case .whisperKitStreaming:
            self = .whisperKitStreaming
        case .appleDictation:
            self = .appleDictation
        case .whisperKit:
            self = .whisperKit
        }
    }

    var diagnosticName: String {
        switch self {
        case .sherpaParaformer:
            "sherpaParaformer"
        case .whisperKitStreaming:
            "whisperKitStreaming"
        case .appleDictation:
            "appleDictation"
        case .whisperKit:
            "whisperKit"
        }
    }

    var backend: RecognitionBackend {
        switch self {
        case .sherpaParaformer:
            .sherpaParaformer
        case .whisperKitStreaming:
            .whisperKitStreaming
        case .appleDictation:
            .appleDictation
        case .whisperKit:
            .whisperKit
        }
    }
}

private struct AudioBuffer: Sendable {
    var samples: [Float]
    var sampleRate: Double
}
