import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(appModel: appModel)
                .tabItem { Label("通用", systemImage: "gearshape") }

            ProfilesSettingsView(appModel: appModel)
                .tabItem { Label("应用配置", systemImage: "rectangle.3.group") }

            LLMSettingsView(appModel: appModel)
                .tabItem { Label("大模型", systemImage: "sparkles") }

            ExternalTriggerSettingsView(appModel: appModel)
                .tabItem { Label("DJI 触发器", systemImage: "dot.radiowaves.left.and.right") }

            PrivacySettingsView(appModel: appModel)
                .tabItem { Label("隐私", systemImage: "lock") }

            AboutSettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(20)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var capturingTarget: HotkeyTarget?

    var body: some View {
        Form {
            Picker("默认模式", selection: selectedModeBinding) {
                ForEach(DictationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("识别引擎", selection: recognitionBackendBinding) {
                ForEach(RecognitionBackend.selectableCases) { backend in
                    Text(label(for: backend)).tag(backend)
                }
            }

            Text(appModel.recognitionBackend.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.recognitionBackend == .whisperKitStreaming {
                TextField("WhisperKit 流式模型", text: whisperKitStreamingModelBinding)
                    .textFieldStyle(.roundedBorder)
                Text("建议先用 small；可填写 large-v3、distil*large-v3 等 WhisperKit 支持的模型名。修改后重启应用加载新模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Apple 原生听写（macOS 26+ SpeechAnalyzer）仍在预留开发中，当前不会出现在可选识别引擎里。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("听写语言", selection: transcriptionLanguageBinding) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            Toggle("保存文本历史", isOn: saveHistoryBinding)
            Toggle("开机启动", isOn: $appModel.launchAtLogin)

            HotkeyRow(
                title: "听写快捷键",
                hotkey: appModel.dictationHotkey,
                isCapturing: capturingTarget == .dictation
            ) {
                capturingTarget = .dictation
            }

            HotkeyRow(
                title: "回车快捷键",
                hotkey: appModel.returnHotkey,
                isCapturing: capturingTarget == .returnKey
            ) {
                capturingTarget = .returnKey
            }

            LabeledContent("中断快捷键", value: appModel.cancelHotkey.displayName)

            if let capturingTarget {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在设置：\(capturingTarget.title)")
                        .font(.headline)
                    Text("请按下新的组合键。必须包含 ⌃/⌥/⇧/⌘ 中至少一个修饰键；按 Esc 取消。")
                        .foregroundStyle(.secondary)

                    HotkeyRecorderView { hotkey in
                        if let hotkey {
                            appModel.updateHotkey(capturingTarget, to: hotkey)
                        }
                        self.capturingTarget = nil
                    }
                    .frame(height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            LabeledContent("快捷键状态", value: appModel.hotkeyStatusMessage)
            HStack {
                LabeledContent("识别模型", value: appModel.modelStatus)
                Spacer()
                Button("下载/重试") {
                    Task { await appModel.downloadSherpaModel() }
                }
                .disabled(appModel.recognitionBackend != .sherpaParaformer)
            }
        }
        .onAppear {
            appModel.refreshSpeechModelStatus()
        }
    }

    private var selectedModeBinding: Binding<DictationMode> {
        Binding(
            get: { appModel.selectedMode },
            set: { appModel.updateSelectedMode($0) }
        )
    }

    private var transcriptionLanguageBinding: Binding<TranscriptionLanguage> {
        Binding(
            get: { appModel.transcriptionLanguage },
            set: { appModel.updateTranscriptionLanguage($0) }
        )
    }

    private var recognitionBackendBinding: Binding<RecognitionBackend> {
        Binding(
            get: { appModel.recognitionBackend },
            set: { appModel.updateRecognitionBackend($0) }
        )
    }

    private var whisperKitStreamingModelBinding: Binding<String> {
        Binding(
            get: { appModel.whisperKitStreamingModel },
            set: { appModel.updateWhisperKitStreamingModel($0) }
        )
    }

    private var saveHistoryBinding: Binding<Bool> {
        Binding(
            get: { appModel.saveHistory },
            set: { appModel.updateSaveHistory($0) }
        )
    }

    private func label(for backend: RecognitionBackend) -> String {
        switch backend {
        case .sherpaParaformer:
            "推荐 · \(backend.title)"
        case .whisperKitStreaming:
            "实验 · \(backend.title)"
        case .appleDictation:
            "预留 · \(backend.title)"
        case .whisperKit:
            backend.title
        }
    }
}

private struct LLMSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Form {
            Toggle("启用大模型优化", isOn: llmEnabledBinding)

            TextField("Base URL", text: llmBaseURLBinding)
                .textFieldStyle(.roundedBorder)
                .disabled(!appModel.llmOptimizationEnabled)

            SecureField("API Key", text: llmAPIKeyBinding)
                .textFieldStyle(.roundedBorder)
                .disabled(!appModel.llmOptimizationEnabled)

            TextField("模型名", text: llmModelBinding)
                .textFieldStyle(.roundedBorder)
                .disabled(!appModel.llmOptimizationEnabled)

            TextField("优化风格", text: llmStyleBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .disabled(!appModel.llmOptimizationEnabled)

            TextField("自定义提示词", text: llmCustomPromptBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(8...14)
                .disabled(!appModel.llmOptimizationEnabled)

            HStack {
                Text("可用变量：{rawTranscript}、{cleanedText}、{mode}、{app}、{style}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认提示词") {
                    appModel.updateLLMCustomPrompt("")
                }
                .disabled(!appModel.llmOptimizationEnabled)
            }

            Text("接口使用 OpenAI 兼容的 /v1/chat/completions。API Key 会存入系统钥匙串。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var llmEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.llmOptimizationEnabled },
            set: { appModel.updateLLMOptimizationEnabled($0) }
        )
    }

    private var llmBaseURLBinding: Binding<String> {
        Binding(
            get: { appModel.llmBaseURL },
            set: { appModel.updateLLMBaseURL($0) }
        )
    }

    private var llmAPIKeyBinding: Binding<String> {
        Binding(
            get: { appModel.llmAPIKey },
            set: { appModel.updateLLMAPIKey($0) }
        )
    }

    private var llmModelBinding: Binding<String> {
        Binding(
            get: { appModel.llmModel },
            set: { appModel.updateLLMModel($0) }
        )
    }

    private var llmStyleBinding: Binding<String> {
        Binding(
            get: { appModel.llmStyleInstruction },
            set: { appModel.updateLLMStyleInstruction($0) }
        )
    }

    private var llmCustomPromptBinding: Binding<String> {
        Binding(
            get: { appModel.llmCustomPrompt },
            set: { appModel.updateLLMCustomPrompt($0) }
        )
    }
}

private struct HotkeyRow: View {
    var title: String
    var hotkey: HotkeyDefinition
    var isCapturing: Bool
    var onCapture: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(hotkey.displayName)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Button(isCapturing ? "等待输入..." : "自定义") {
                onCapture()
            }
        }
    }
}

private struct ProfilesSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        List(appModel.appProfiles) { profile in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                    Text(profile.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(profile.defaultMode.title)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExternalTriggerSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Form {
            Toggle("启用 DJI Mic 触发器", isOn: enabledBinding)

            LabeledContent("当前状态", value: appModel.externalTriggerStatus.title)
            LabeledContent("匹配 vendor_id", value: "\(appModel.externalTriggerVendorID)")
            LabeledContent("匹配 product_id", value: "\(appModel.externalTriggerProductID)")

            Toggle("阻止原始音量增加事件", isOn: suppressVolumeBinding)
                .disabled(!appModel.externalTriggerEnabled)

            Picker("取消修饰键", selection: cancelModifierBinding) {
                ForEach(ExternalTriggerCancelModifier.allCases) { modifier in
                    Text(modifier.title).tag(modifier)
                }
            }
            .disabled(!appModel.externalTriggerEnabled)

            HStack {
                Button("重新检测") {
                    appModel.recheckExternalTrigger()
                }
                Button("测试 DJI 按钮") {
                    appModel.testExternalTriggerButton()
                }
            }

            if let event = appModel.externalTriggerLastEvent {
                LabeledContent("最近事件", value: event.summary)
            } else {
                LabeledContent("最近事件", value: "尚未收到")
            }

            Text("单击 DJI 按钮会执行当前主动作：开始听写 / 完成输入 / 发送回车。按住取消修饰键再按 DJI 按钮会中断当前流程，默认 Ctrl。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.externalTriggerSuppressVolume && appModel.externalTriggerStatus == .permissionMissing {
                Text("阻止系统音量变化需要输入监控/辅助功能相关权限。如果无法创建 Event Tap，请先到系统设置的隐私与安全性中允许 VoxForge 声铸。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("检测到的设备") {
                if appModel.externalTriggerDevices.isEmpty {
                    Text("尚未检测到 HID 或音频输入设备。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.externalTriggerDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                Text("\(device.sourceType.rawValue) · vendor \(device.vendorDisplay) · product \(device.productDisplay) · \(device.transport)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if device.isMatched {
                                Text("当前匹配")
                                    .foregroundStyle(.green)
                            } else if device.sourceType == .hid && device.vendorID != nil && device.productID != nil {
                                Button("选择") {
                                    appModel.selectExternalTriggerDevice(device)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            appModel.startExternalTriggerIfNeeded()
            appModel.recheckExternalTrigger()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.externalTriggerEnabled },
            set: { appModel.updateExternalTriggerEnabled($0) }
        )
    }

    private var suppressVolumeBinding: Binding<Bool> {
        Binding(
            get: { appModel.externalTriggerSuppressVolume },
            set: { appModel.updateExternalTriggerSuppressVolume($0) }
        )
    }

    private var cancelModifierBinding: Binding<ExternalTriggerCancelModifier> {
        Binding(
            get: { appModel.externalTriggerCancelModifier },
            set: { appModel.updateExternalTriggerCancelModifier($0) }
        )
    }
}

private struct PrivacySettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VoxForge 声铸默认本地处理语音，不保存原始音频。")
                .foregroundStyle(.secondary)

            Button("请求辅助功能权限") {
                appModel.requestAccessibility()
            }

            Button("清空文本历史", role: .destructive) {
                appModel.clearHistory()
            }

            Toggle("保留录音调试文件", isOn: keepDebugRecordingsBinding)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keepDebugRecordingsBinding: Binding<Bool> {
        Binding(
            get: { appModel.keepDebugRecordings },
            set: { appModel.updateKeepDebugRecordings($0) }
        )
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "local"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                TypeMoreAvatarIcon(state: .idle, style: .header)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text("VoxForge 声铸")
                        .font(.largeTitle.weight(.semibold))
                    Text("面向 AI 编程的语音输入法")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("版本 \(version)（\(build)）")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            LabeledContent("作者", value: "super dan")
            LabeledContent("定位", value: "面向 AI 编程的全局语音输入增强器")

            Text("VoxForge 声铸用快捷键或 DJI Mic 按钮启动本地听写，将口语锻造成可直接发送的编程提示词、消息或命令，并在需要时发送回车。它默认尽量在本机处理语音，普通配置与历史记录保存在本地。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("建议把它放在菜单栏常驻使用：需要输入时说话，结束后自动粘贴；遇到异常可随时中断流程。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
