import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var sessionState: DictationSessionState = .idle
    var selectedMode: DictationMode = .codingPrompt
    var statusMessage = "准备好进行 vibe coding"
    var lastTranscript = ""
    var lastTargetApplication: RunningApplicationInfo?
    var appProfiles: [AppProfile] = AppProfile.defaults
    var personalDictionary: [DictionaryEntry] = DictionaryEntry.defaults
    var transcriptionLanguage: TranscriptionLanguage
    var recognitionBackend: RecognitionBackend
    var speechModelState: SpeechModelState = .unchecked
    var saveHistory = true
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
    var whisperKitStreamingModel: String
    var autoSubmitAfterDictation = false
    var externalTriggerEnabled: Bool
    var externalTriggerVendorID: Int
    var externalTriggerProductID: Int
    var externalTriggerSuppressVolume: Bool
    var externalTriggerCancelModifier: ExternalTriggerCancelModifier
    var externalTriggerStatus: ExternalTriggerStatus = .disabled
    var externalTriggerDevices: [ExternalTriggerDevice] = []
    var externalTriggerLastEvent: ExternalTriggerLastEvent?

    private let audioRecorder: AudioRecordingService
    private let streamingAudioRecorder: LiveAudioRecordingService
    private let transcriptionEngine: TranscriptionEngine
    private let sherpaStreamingEngine: StreamingSpeechEngine
    private let whisperKitStreamingEngine: StreamingSpeechEngine
    private let llmOptimizationService: LLMOptimizationService
    private let postProcessor: PostProcessingService
    private let textInsertionService: TextInsertionService
    private let permissionCoordinator: PermissionCoordinator
    private let hotkeyCoordinator: HotkeyCoordinator
    private let externalTriggerService: ExternalTriggerService
    private let foregroundApplicationTracker = ForegroundApplicationTracker()
    private let sherpaModelManager: SherpaModelManager
    private var recordingStart: Date?
    private var activeDictationPath: ActiveDictationPath?
    private let historyStore = HistoryStore()
    private let settingsStore = SettingsStore()
    private let keychainStore = KeychainStore()
    private let hudController = DictationHUDController()
    private var activeOperationID: UUID?

    init(
        audioRecorder: AudioRecordingService = AVAudioEngineRecordingService(),
        streamingAudioRecorder: LiveAudioRecordingService = AVAudioEngineLiveRecordingService(),
        transcriptionEngine: TranscriptionEngine = WhisperKitTranscriptionEngine(),
        sherpaStreamingEngine: StreamingSpeechEngine? = nil,
        whisperKitStreamingEngine: StreamingSpeechEngine? = nil,
        sherpaModelManager: SherpaModelManager = SherpaModelManager(),
        llmOptimizationService: LLMOptimizationService = OpenAICompatibleOptimizationService(),
        postProcessor: PostProcessingService = CodingPromptPostProcessor(),
        textInsertionService: TextInsertionService = PasteboardTextInsertionService(),
        permissionCoordinator: PermissionCoordinator = SystemPermissionCoordinator(),
        hotkeyCoordinator: HotkeyCoordinator = CarbonHotkeyCoordinator()
    ) {
        self.audioRecorder = audioRecorder
        self.streamingAudioRecorder = streamingAudioRecorder
        self.transcriptionEngine = transcriptionEngine
        self.sherpaModelManager = sherpaModelManager
        self.sherpaStreamingEngine = sherpaStreamingEngine ?? SherpaParaformerStreamingEngine(modelManager: sherpaModelManager)
        let persistedWhisperKitModel = settingsStore.whisperKitStreamingModel
        self.whisperKitStreamingEngine = whisperKitStreamingEngine ?? WhisperKitStreamingEngine(modelName: persistedWhisperKitModel)
        self.llmOptimizationService = llmOptimizationService
        self.postProcessor = postProcessor
        self.textInsertionService = textInsertionService
        self.permissionCoordinator = permissionCoordinator
        self.hotkeyCoordinator = hotkeyCoordinator
        self.dictationHotkey = settingsStore.dictationHotkey
        self.returnHotkey = settingsStore.returnHotkey
        self.saveHistory = settingsStore.saveHistory
        self.selectedMode = settingsStore.selectedMode
        self.transcriptionLanguage = settingsStore.transcriptionLanguage
        let persistedBackend = settingsStore.recognitionBackend
        self.recognitionBackend = persistedBackend
        let initialSpeechModelState = sherpaModelManager.status()
        self.speechModelState = initialSpeechModelState
        self.modelStatus = initialSpeechModelState.title
        self.accessibilityPermissionGranted = permissionCoordinator.hasAccessibilityPermission
        self.transcriptRecords = historyStore.load()
        self.llmOptimizationEnabled = settingsStore.llmOptimizationEnabled
        self.llmBaseURL = settingsStore.llmBaseURL
        self.llmModel = settingsStore.llmModel
        self.llmStyleInstruction = settingsStore.llmStyleInstruction
        self.llmCustomPrompt = settingsStore.llmCustomPrompt
        self.keepDebugRecordings = settingsStore.keepDebugRecordings
        self.whisperKitStreamingModel = persistedWhisperKitModel
        self.llmAPIKey = keychainStore.string(for: "llmAPIKey")
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

    func profile(for bundleIdentifier: String) -> AppProfile {
        appProfiles.first { $0.bundleIdentifier == bundleIdentifier } ?? .generic
    }

    func configureHotkeysIfNeeded() {
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
    }

    func startExternalTriggerIfNeeded() {
        externalTriggerService.start()
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
        case .processing, .optimizing, .inserting:
            statusMessage = "当前听写正在处理中"
        }
    }

    func startDictation() async {
        let operationID = UUID()
        activeOperationID = operationID
        errorMessage = nil
        transition(to: .processing, message: "正在检查麦克风权限")
        guard await permissionCoordinator.ensureMicrophonePermission() else {
            guard isActiveOperation(operationID) else { return }
            fail("需要麦克风权限才能听写。")
            return
        }
        guard isActiveOperation(operationID) else { return }

        lastTargetApplication = foregroundApplicationTracker.targetApplication()

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
            fail("Apple 原生听写后端预留给 macOS 26+ SpeechAnalyzer，当前版本尚未启用。请切换到中文极速本地或 WhisperKit 流式。")
            return
        case .whisperKit:
            break
        }

        do {
            try audioRecorder.startRecording()
            recordingStart = Date()
            activeDictationPath = .whisperKit
            guard isActiveOperation(operationID) else {
                _ = try? audioRecorder.stopRecording()
                return
            }
            transition(to: .recording, message: "正在听写：WhisperKit 兼容")
        } catch {
            guard isActiveOperation(operationID) else { return }
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
        do {
            transition(to: .processing, message: preparingMessage)
            let state = try await engine.prepare { [weak self] state in
                Task { @MainActor in
                    self?.speechModelState = state
                    self?.modelStatus = state.title
                    self?.hudController.show(state: .processing, message: state.title)
                }
            }
            guard isActiveOperation(operationID) else {
                await engine.cancel()
                return
            }
            speechModelState = state
            modelStatus = state.title

            try await engine.startSession(
                mode: selectedMode,
                language: transcriptionLanguage,
                dictionary: personalDictionary,
                onPartial: { [weak self] partial in
                    Task { @MainActor in
                        guard self?.isActiveOperation(operationID) == true else { return }
                        self?.lastTranscript = partial
                        self?.hudController.show(state: .recording, message: "正在听写：实时识别中", preview: partial)
                    }
                }
            )

            try streamingAudioRecorder.startStreaming(keepDebugFile: keepDebugRecordings) { samples, sampleRate in
                Task {
                    await engine.acceptAudio(samples: samples, sampleRate: sampleRate)
                }
            }
            guard isActiveOperation(operationID) else {
                _ = try? streamingAudioRecorder.stopStreaming()
                await engine.cancel()
                return
            }
            recordingStart = Date()
            activeDictationPath = ActiveDictationPath(backend: backend)
            transition(to: .recording, message: recordingMessage)
        } catch {
            guard isActiveOperation(operationID) else { return }
            await engine.cancel()
            activeDictationPath = nil
            speechModelState = .failed(error.localizedDescription)
            modelStatus = speechModelState.title
            fail("\(failurePrefix)：\(error.localizedDescription)。当前设置为 \(backend.title)，不会自动切换其他识别引擎。")
        }
    }

    private func finishStreamingDictation(engine: StreamingSpeechEngine, operationID: UUID, finishMessage: String) async {
        transition(to: .processing, message: finishMessage, preview: lastTranscript)

        do {
            let recording = try streamingAudioRecorder.stopStreaming()
            let result = try await engine.finish(recording: recording)
            guard isActiveOperation(operationID) else {
                await engine.cancel()
                return
            }
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
            activeDictationPath = nil
            await engine.cancel()
            fail("听写失败：\(error.localizedDescription)")
        }
    }

    private func finishWhisperKitDictation(operationID: UUID) async {
        transition(to: .processing, message: "正在用 WhisperKit 本地转写")

        do {
            let audio = try audioRecorder.stopRecording()
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
            fail("听写失败：\(error.localizedDescription)")
        }
    }

    private func completeDictation(rawTranscript: String, duration: TimeInterval, debugAudioURL: URL?, backend: RecognitionBackend, operationID: UUID) async throws {
        guard isActiveOperation(operationID) else { return }
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
            } catch {
                guard isActiveOperation(operationID) else { return }
                statusMessage = "大模型优化失败，已使用本地结果：\(error.localizedDescription)"
                hudController.show(state: .optimizing, message: "大模型优化失败，已使用本地结果", preview: processed)
            }
        }

        lastTranscript = finalText
        autoSubmitAfterDictation = false

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
        try await textInsertionService.insert(finalText, targetBundleIdentifier: targetApp.bundleIdentifier)
        guard isActiveOperation(operationID) else { return }
        saveTranscript(finalText, rawTranscript: rawTranscript, duration: duration, targetApp: targetApp, inserted: true, optimizedWithLLM: optimizedWithLLM)
        cleanupDebugAudioIfNeeded(debugAudioURL)

        if autoSubmitAfterDictation {
            sendReturn()
        } else {
            transition(to: .readyToSubmit, message: "已输入到 \(targetApp.displayName)。再次按听写快捷键发送回车。", preview: finalText)
            if NSApp.isActive && !NSApp.isHidden {
                hudController.showReadyToSubmit(message: "已输入，下一次按键发送")
            }
        }
    }

    func cancelDictation() {
        interruptCurrentFlow()
    }

    func interruptCurrentFlow() {
        guard sessionState != .idle else {
            hudController.hide()
            return
        }
        activeOperationID = nil
        if activeDictationPath == .sherpaParaformer {
            _ = try? streamingAudioRecorder.stopStreaming()
            Task { await sherpaStreamingEngine.cancel() }
        } else if activeDictationPath == .whisperKitStreaming {
            _ = try? streamingAudioRecorder.stopStreaming()
            Task { await whisperKitStreamingEngine.cancel() }
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
                autoSubmitAfterDictation = false
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

        permissionCoordinator.openAccessibilityPrompt()
        fail(accessibilityHelpMessage(action: action))
        return false
    }

    private func isActiveOperation(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
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
        }
    }

    func clearHistory() {
        transcriptRecords = []
        historyStore.save([])
        statusMessage = "历史记录已清空"
    }

    func updateHotkey(_ target: HotkeyTarget, to hotkey: HotkeyDefinition) {
        switch target {
        case .dictation:
            dictationHotkey = hotkey
            settingsStore.dictationHotkey = hotkey
        case .returnKey:
            returnHotkey = hotkey
            settingsStore.returnHotkey = hotkey
        case .cancel:
            cancelHotkey = hotkey
        }
        configureHotkeysIfNeeded()
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
            modelStatus = "Apple 原生听写预留给 macOS 26+"
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

    func updateLLMOptimizationEnabled(_ enabled: Bool) {
        llmOptimizationEnabled = enabled
        settingsStore.llmOptimizationEnabled = enabled
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
        keychainStore.setString(value, for: "llmAPIKey")
    }

    func updateKeepDebugRecordings(_ enabled: Bool) {
        keepDebugRecordings = enabled
        settingsStore.keepDebugRecordings = enabled
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

    var llmConfiguration: LLMOptimizationConfiguration {
        LLMOptimizationConfiguration(
            isEnabled: llmOptimizationEnabled,
            baseURL: llmBaseURL,
            apiKey: llmAPIKey,
            model: llmModel,
            styleInstruction: llmStyleInstruction,
            customPrompt: settingsStore.llmPromptTemplate(for: selectedMode)
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
        historyStore.save(transcriptRecords)
    }

    private func transition(to state: DictationSessionState, message: String, preview: String? = nil) {
        sessionState = state
        statusMessage = message
        if state == .idle || state == .readyToSubmit || state == .inserting {
            return
        }
        hudController.show(state: state, message: message, preview: preview)
    }

    private func cleanupRecordingIfNeeded(_ audioURL: URL) {
        guard !keepDebugRecordings else { return }
        try? FileManager.default.removeItem(at: audioURL)
    }

    private func cleanupDebugAudioIfNeeded(_ audioURL: URL?) {
        guard let audioURL, !keepDebugRecordings else { return }
        try? FileManager.default.removeItem(at: audioURL)
    }

    private func performanceStatus(for result: StreamingTranscriptionResult) -> String {
        let firstPartial = result.firstPartialLatency.map { String(format: "%.2fs 首字", $0) } ?? "无首字"
        let final = String(format: "%.2fs 收尾", result.finalizationLatency)
        let rtf = String(format: "RTF %.2f", result.realTimeFactor)
        return "\(result.backend.title) 已就绪 · \(firstPartial) · \(final) · \(rtf)"
    }

    private func fail(_ message: String) {
        activeOperationID = nil
        sessionState = .failed
        errorMessage = message
        statusMessage = message
        hudController.showFailure(message: message)
    }
}

private enum ActiveDictationPath {
    case sherpaParaformer
    case whisperKitStreaming
    case whisperKit

    init(backend: RecognitionBackend) {
        switch backend {
        case .sherpaParaformer:
            self = .sherpaParaformer
        case .whisperKitStreaming:
            self = .whisperKitStreaming
        case .whisperKit, .appleDictation:
            self = .whisperKit
        }
    }
}
