import SwiftUI

struct MenuBarContentView: View {
    @Bindable var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(appModel.primaryActionTitle) {
            Task { await appModel.toggleDictation() }
        }

        Button("中断当前流程") {
            appModel.interruptCurrentFlow()
        }
        .disabled(appModel.sessionState == .idle)

        Button("发送回车") {
            appModel.sendReturn()
        }

        Divider()

        Picker("模式", selection: selectedModeBinding) {
            ForEach(DictationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }

        Divider()

        Button("打开 VoxForge") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("设置") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("退出") {
            NSApp.terminate(nil)
        }
    }

    private var selectedModeBinding: Binding<DictationMode> {
        Binding(
            get: { appModel.selectedMode },
            set: { appModel.updateSelectedMode($0) }
        )
    }
}
