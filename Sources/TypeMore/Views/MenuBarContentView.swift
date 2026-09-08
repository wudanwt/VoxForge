import SwiftUI

struct MenuBarContentView: View {
    @Bindable var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if appModel.applicationOperatingMode == .fullDictation {
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
        } else {
            Text("DJI 桥接：\(appModel.externalTriggerStatus.title)")
            Text("下一次：\(appModel.bridgeNextActionTitle)")

            Button("测试发送 \(appModel.bridgeTargetHotkey.displayName)") {
                appModel.sendBridgeTargetHotkey()
            }

            Button("重置三段循环") {
                appModel.resetBridgeClickCycle()
            }

            if let event = appModel.externalTriggerLastEvent {
                Text("最近：\(event.summary)")
            }
        }

        Divider()

        Button(appModel.applicationOperatingMode == .fullDictation ? "打开 VoxForge" : "打开桥接状态") {
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
