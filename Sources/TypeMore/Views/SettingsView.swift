import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(appModel: appModel)
                .tabItem { Label("通用", systemImage: "gearshape") }

            if appModel.applicationOperatingMode == .fullDictation {
                ProfilesSettingsView(appModel: appModel)
                    .tabItem { Label("应用配置", systemImage: "rectangle.3.group") }

                DictionarySettingsView(appModel: appModel)
                    .tabItem { Label("词典", systemImage: "text.book.closed") }

                LLMSettingsView(appModel: appModel)
                    .tabItem { Label("大模型", systemImage: "sparkles") }
            }

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
    @State private var isCapturingBridgeHotkey = false

    var body: some View {
        Form {
            Picker("运行模式", selection: applicationOperatingModeBinding) {
                ForEach(ApplicationOperatingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Text(appModel.applicationOperatingMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.applicationOperatingMode == .djiHotkeyBridge {
                HotkeyRow(
                    title: "目标软件快捷键",
                    hotkey: appModel.bridgeTargetHotkey,
                    isCapturing: isCapturingBridgeHotkey
                ) {
                    isCapturingBridgeHotkey = true
                }

                if isCapturingBridgeHotkey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("正在设置：目标软件快捷键")
                            .font(.headline)
                        Text("请按下外部听写软件使用的组合键；按 Esc 取消。")
                            .foregroundStyle(.secondary)

                        HotkeyRecorderView { hotkey in
                            if let hotkey {
                                appModel.updateBridgeTargetHotkey(hotkey)
                            }
                            isCapturingBridgeHotkey = false
                        }
                        .frame(height: 52)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                LabeledContent("桥接状态", value: appModel.bridgeStatusMessage)
                LabeledContent("下一次 DJI 按钮", value: appModel.bridgeNextActionTitle)

                Button("测试发送 \(appModel.bridgeTargetHotkey.displayName)") {
                    appModel.sendBridgeTargetHotkey()
                }

                Button("重置三段循环") {
                    appModel.resetBridgeClickCycle()
                }

                Toggle("开机启动", isOn: $appModel.launchAtLogin)

                Text("DJI 按钮按三次为一轮：开始听写、结束听写、发送回车。桥接模式不会请求麦克风权限，也不会加载语音模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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

                Text(RecognitionBackend.isAppleDictationSupported ? "Apple 原生听写使用 macOS 26+ SpeechAnalyzer，作为实验后端可选。" : "Apple 原生听写需要 macOS 26+ SpeechAnalyzer，当前系统不会显示该后端。")
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

                HotkeyRow(
                    title: "中断快捷键",
                    hotkey: appModel.cancelHotkey,
                    isCapturing: capturingTarget == .cancel
                ) {
                    capturingTarget = .cancel
                }

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
        }
        .onAppear {
            if appModel.applicationOperatingMode == .fullDictation {
                appModel.refreshSpeechModelStatus()
            }
        }
    }

    private var applicationOperatingModeBinding: Binding<ApplicationOperatingMode> {
        Binding(
            get: { appModel.applicationOperatingMode },
            set: { appModel.updateApplicationOperatingMode($0) }
        )
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
            "实验 · \(backend.title)"
        case .whisperKit:
            backend.title
        }
    }
}

private struct LLMSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection("连接配置") {
                    Toggle("启用大模型优化", isOn: llmEnabledBinding)

                    LabeledContent("Base URL") {
                        TextField("Base URL", text: llmBaseURLBinding)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!appModel.llmOptimizationEnabled)
                    }

                    LabeledContent("API Key") {
                        SecureField("API Key", text: llmAPIKeyBinding)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!appModel.llmOptimizationEnabled)
                    }

                    LabeledContent("模型名") {
                        TextField("模型名", text: llmModelBinding)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!appModel.llmOptimizationEnabled)
                    }

                    Text("接口使用 OpenAI 兼容的 /v1/chat/completions。API Key 会存入系统钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection("优化行为") {
                    LabeledContent("优化风格") {
                        TextField("优化风格", text: llmStyleBinding, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .disabled(!appModel.llmOptimizationEnabled)
                    }
                }

                settingsSection("提示词模板") {
                    Picker("当前模式", selection: llmPromptTemplateModeBinding) {
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!appModel.llmOptimizationEnabled)

                    HStack {
                        Text(appModel.isUsingDefaultLLMPromptTemplate(for: appModel.llmPromptTemplateMode) ? "正在使用默认提示词" : "正在使用自定义提示词")
                            .font(.caption)
                            .foregroundStyle(appModel.isUsingDefaultLLMPromptTemplate(for: appModel.llmPromptTemplateMode) ? Color.secondary : Color.blue)
                        Spacer()
                        Button("恢复当前默认") {
                            appModel.resetLLMPromptTemplate(for: appModel.llmPromptTemplateMode)
                        }
                        .disabled(!appModel.llmOptimizationEnabled || appModel.isUsingDefaultLLMPromptTemplate(for: appModel.llmPromptTemplateMode))

                        Button("恢复全部默认", role: .destructive) {
                            appModel.resetAllLLMPromptTemplates()
                        }
                        .disabled(!appModel.llmOptimizationEnabled)
                    }

                    TextEditor(text: llmPromptTemplateBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                        .disabled(!appModel.llmOptimizationEnabled)

                    Text("可用变量：{rawTranscript}、{cleanedText}、{mode}、{app}、{style}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            appModel.loadLLMAPIKeyIfNeeded()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))
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

    private var llmPromptTemplateModeBinding: Binding<DictationMode> {
        Binding(
            get: { appModel.llmPromptTemplateMode },
            set: { appModel.updateLLMPromptTemplateMode($0) }
        )
    }

    private var llmPromptTemplateBinding: Binding<String> {
        Binding(
            get: { appModel.llmPromptTemplate(for: appModel.llmPromptTemplateMode) },
            set: { appModel.updateLLMPromptTemplate($0, for: appModel.llmPromptTemplateMode) }
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

private struct DictionarySettingsView: View {
    @Bindable var appModel: AppModel
    @State private var testText = ""
    @State private var testBundleIdentifier = "*"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自定义词典")
                        .font(.title2.weight(.semibold))
                    Text("把人名、项目名、产品名或命令写成个人词条。开启大模型优化后，模型会结合原始转写、上下文和常见误听判断是否应改成标准写法。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        appModel.addDictionaryEntry()
                    } label: {
                        Label("新增词条", systemImage: "plus")
                    }

                    Button("恢复默认", role: .destructive) {
                        appModel.resetPersonalDictionary()
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    if appModel.personalDictionary.isEmpty {
                        Text("还没有词条。可以添加标准词条，例如“吴律”，并按需补充常见误听“五律、无虑”。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(appModel.personalDictionary) { entry in
                            DictionaryEntryRow(
                                term: binding(for: entry, keyPath: \.term),
                                aliases: aliasesBinding(for: entry),
                                note: binding(for: entry, keyPath: \.note),
                                isEnabled: enabledBinding(for: entry),
                                behavior: behaviorBinding(for: entry),
                                scopeBundleIdentifier: scopeBinding(for: entry),
                                appProfiles: appModel.appProfiles
                            ) {
                                appModel.deleteDictionaryEntry(entry)
                            }
                        }
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))

                Text("提示：智能纠错由大模型结合上下文判断；固定替换在本地确定执行。个人词典不会作为识别热词强行偏置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GroupBox("试一试固定替换") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("目标应用", selection: $testBundleIdentifier) {
                            Text("所有应用").tag("*")
                            ForEach(appModel.appProfiles.filter { $0.bundleIdentifier != "*" }) { profile in
                                Text(profile.displayName).tag(profile.bundleIdentifier)
                            }
                        }
                        TextField("输入一段示例文本", text: $testText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        LabeledContent("替换结果") {
                            Text(appModel.previewFixedDictionaryReplacement(
                                testText,
                                targetBundleIdentifier: testBundleIdentifier
                            ))
                            .textSelection(.enabled)
                        }
                        Text("这里只预览固定替换；智能纠错需要在实际听写时由大模型判断。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func binding(for entry: DictionaryEntry, keyPath: WritableKeyPath<DictionaryEntry, String>) -> Binding<String> {
        Binding(
            get: {
                appModel.personalDictionary.first(where: { $0.id == entry.id })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                guard var updated = appModel.personalDictionary.first(where: { $0.id == entry.id }) else { return }
                updated[keyPath: keyPath] = value
                appModel.updateDictionaryEntry(updated)
            }
        )
    }

    private func aliasesBinding(for entry: DictionaryEntry) -> Binding<String> {
        Binding(
            get: {
                appModel.personalDictionary.first(where: { $0.id == entry.id })?.aliases.joined(separator: "、") ?? ""
            },
            set: { value in
                guard var updated = appModel.personalDictionary.first(where: { $0.id == entry.id }) else { return }
                updated.aliases = value
                    .components(separatedBy: CharacterSet(charactersIn: "、,，;；\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                appModel.updateDictionaryEntry(updated)
            }
        )
    }

    private func enabledBinding(for entry: DictionaryEntry) -> Binding<Bool> {
        Binding(
            get: {
                appModel.personalDictionary.first(where: { $0.id == entry.id })?.isEnabled ?? true
            },
            set: { value in
                guard var updated = appModel.personalDictionary.first(where: { $0.id == entry.id }) else { return }
                updated.isEnabled = value
                appModel.updateDictionaryEntry(updated)
            }
        )
    }

    private func behaviorBinding(for entry: DictionaryEntry) -> Binding<DictionaryEntryBehavior> {
        Binding(
            get: {
                appModel.personalDictionary.first(where: { $0.id == entry.id })?.behavior ?? .smart
            },
            set: { value in
                guard var updated = appModel.personalDictionary.first(where: { $0.id == entry.id }) else { return }
                updated.behavior = value
                appModel.updateDictionaryEntry(updated)
            }
        )
    }

    private func scopeBinding(for entry: DictionaryEntry) -> Binding<String> {
        Binding(
            get: {
                guard let scope = appModel.personalDictionary.first(where: { $0.id == entry.id })?.scope,
                      !scope.isGlobal else { return "*" }
                return scope.applicationBundleIdentifiers.first ?? "*"
            },
            set: { value in
                guard var updated = appModel.personalDictionary.first(where: { $0.id == entry.id }) else { return }
                updated.scope = value == "*"
                    ? .global
                    : DictionaryEntryScope(applicationBundleIdentifiers: [value])
                appModel.updateDictionaryEntry(updated)
            }
        )
    }
}

private struct DictionaryEntryRow: View {
    @Binding var term: String
    @Binding var aliases: String
    @Binding var note: String
    @Binding var isEnabled: Bool
    @Binding var behavior: DictionaryEntryBehavior
    @Binding var scopeBundleIdentifier: String
    var appProfiles: [AppProfile]
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("启用", isOn: $isEnabled)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除词条")
            }

            LabeledContent("标准词条") {
                TextField("例如：吴律", text: $term)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Picker("处理方式", selection: $behavior) {
                    ForEach(DictionaryEntryBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Picker("作用范围", selection: $scopeBundleIdentifier) {
                    Text("所有应用").tag("*")
                    ForEach(appProfiles.filter { $0.bundleIdentifier != "*" }) { profile in
                        Text(profile.displayName).tag(profile.bundleIdentifier)
                    }
                }
            }

            LabeledContent("常见误听") {
                TextField("例如：五律、无虑", text: $aliases)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("说明") {
                TextField("例如：我女儿名字，人名", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }


            Text(behavior == .fixed
                 ? "命中常见误听后始终替换，不判断上下文。"
                 : "开启大模型优化后，结合上下文判断是否修正；常见误听可留空。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ExternalTriggerSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Form {
            if appModel.applicationOperatingMode == .fullDictation {
                Toggle("启用 DJI Mic 触发器", isOn: enabledBinding)
            } else {
                LabeledContent("DJI Mic 触发器", value: "桥接模式下始终启用")
                LabeledContent("目标快捷键", value: appModel.bridgeTargetHotkey.displayName)
                LabeledContent("下一次动作", value: appModel.bridgeNextActionTitle)
            }

            LabeledContent("当前状态", value: appModel.externalTriggerStatus.title)
            LabeledContent("匹配 vendor_id", value: "\(appModel.externalTriggerVendorID)")
            LabeledContent("匹配 product_id", value: "\(appModel.externalTriggerProductID)")

            Toggle("阻止原始音量增加事件", isOn: suppressVolumeBinding)
                .disabled(!appModel.isExternalTriggerEffectivelyEnabled)

            if appModel.applicationOperatingMode == .fullDictation {
                Picker("取消修饰键", selection: cancelModifierBinding) {
                    ForEach(ExternalTriggerCancelModifier.allCases) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                .disabled(!appModel.externalTriggerEnabled)
            }

            HStack {
                Button("重新检测") {
                    appModel.recheckExternalTrigger()
                }
                Button(appModel.applicationOperatingMode == .djiHotkeyBridge ? "测试发送快捷键" : "测试 DJI 按钮") {
                    appModel.testExternalTriggerButton()
                }
            }

            if let event = appModel.externalTriggerLastEvent {
                LabeledContent("最近事件", value: event.summary)
            } else {
                LabeledContent("最近事件", value: "尚未收到")
            }

            Text(appModel.applicationOperatingMode == .djiHotkeyBridge
                 ? "桥接模式按三次为一轮：前两次发送目标快捷键 \(appModel.bridgeTargetHotkey.displayName)，第三次发送普通回车，然后重新开始。"
                 : "单击 DJI 按钮会执行当前主动作：开始听写 / 完成输入 / 发送回车。按住取消修饰键再按 DJI 按钮会中断当前流程，默认 Ctrl。")
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
            Text(appModel.applicationOperatingMode == .djiHotkeyBridge
                 ? "桥接模式不会录音，也不需要麦克风权限；发送快捷键和阻止音量事件可能需要辅助功能或输入监控权限。"
                 : "VoxForge 声铸默认本地处理语音，不保存原始音频。")
                .foregroundStyle(.secondary)

            Button("请求辅助功能权限") {
                appModel.requestAccessibility()
            }

            Button("清空文本历史", role: .destructive) {
                appModel.clearHistory()
            }

            Picker("历史保留", selection: historyRetentionBinding) {
                ForEach(HistoryRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }

            Toggle("保留录音调试文件", isOn: keepDebugRecordingsBinding)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("诊断日志")
                    .font(.headline)

                Picker("失败录音", selection: diagnosticAudioRetentionBinding) {
                    ForEach(DiagnosticAudioRetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                if let summary = appModel.recentDiagnosticFailureSummary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近失败：\(summary.phase)")
                        Text(summary.timestamp.formatted(date: .abbreviated, time: .standard))
                        Text(summary.error)
                        if let backend = summary.backend {
                            Text("识别引擎：\(backend)")
                        }
                        if let audioInput = summary.audioInput {
                            Text("输入设备：\(audioInput)")
                        }
                        Text(summary.debugAudioPath == nil ? "调试录音：无" : "调试录音：有")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("尚无失败记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("导出诊断包") {
                        appModel.exportDiagnosticsPackage()
                    }
                    Button("清空诊断日志", role: .destructive) {
                        appModel.clearDiagnostics()
                    }
                }

                Text(appModel.diagnosticStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

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

    private var historyRetentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { appModel.historyRetention },
            set: { appModel.updateHistoryRetention($0) }
        )
    }

    private var diagnosticAudioRetentionBinding: Binding<DiagnosticAudioRetentionPolicy> {
        Binding(
            get: { appModel.diagnosticAudioRetentionPolicy },
            set: { appModel.updateDiagnosticAudioRetentionPolicy($0) }
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
