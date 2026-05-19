import SwiftUI

struct ContentView: View {
    @Bindable var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selectedModeBinding)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(appModel: appModel)
                PermissionBannerView(appModel: appModel)
                ModePickerView(selectedMode: selectedModeBinding)
                LastTranscriptView(text: appModel.lastTranscript)
                HistoryListView(records: Array(appModel.transcriptRecords.prefix(12)))
            }
            .padding(24)
            .frame(minWidth: 680, minHeight: 560, alignment: .topLeading)
        }
        .onAppear {
            appModel.refreshPermissions()
            appModel.refreshSpeechModelStatus()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                appModel.refreshPermissions()
            }
        }
    }

    private var selectedModeBinding: Binding<DictationMode> {
        Binding(
            get: { appModel.selectedMode },
            set: { appModel.updateSelectedMode($0) }
        )
    }
}

private struct HeaderView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            TypeMoreAvatarIcon(state: appModel.sessionState, style: .header)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("VoxForge 声铸")
                    .font(.largeTitle.weight(.semibold))
                Text(appModel.statusMessage)
                    .foregroundStyle(.secondary)
                Text(appModel.hotkeyStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(appModel.primaryActionTitle) {
                Task { await appModel.toggleDictation() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.sessionState == .processing || appModel.sessionState == .inserting || appModel.sessionState == .optimizing)

            Button("发送回车") {
                appModel.sendReturn()
            }
        }
    }
}

private struct PermissionBannerView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        if let error = appModel.errorMessage {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .lineLimit(2)
                Spacer()
                if error.contains("辅助功能") {
                    Button("打开辅助功能设置") {
                        appModel.requestAccessibility()
                    }
                }
                Button("刷新状态") {
                    appModel.refreshPermissions()
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ModePickerView: View {
    @Binding var selectedMode: DictationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("模式", selection: $selectedMode) {
                ForEach(DictationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedMode.description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LastTranscriptView: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近输入")
                .font(.headline)
            Text(text.isEmpty ? "还没有输入记录。按下默认快捷键 ⌃⌥D 开始，或在设置中自定义。" : text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
