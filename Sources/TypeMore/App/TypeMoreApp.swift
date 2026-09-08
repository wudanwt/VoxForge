import AppKit
import SwiftUI

@main
struct TypeMoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("VoxForge 声铸", id: "main") {
            ContentView(appModel: appModel)
                .onAppear {
                    appModel.startAppServicesAfterLaunch()
                }
        }
        .commands {
            if appModel.applicationOperatingMode == .fullDictation {
                CommandMenu("听写") {
                    Button(appModel.primaryActionTitle) {
                        Task { await appModel.toggleDictation() }
                    }
                    .keyboardShortcut("d", modifiers: [.command, .option])

                    Button("发送回车") {
                        appModel.sendReturn()
                    }
                    .keyboardShortcut(.return, modifiers: [.command, .option])

                    Button("取消听写") {
                        appModel.cancelDictation()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            } else {
                CommandMenu("DJI 桥接") {
                    Button("测试发送目标快捷键") {
                        appModel.sendBridgeTargetHotkey()
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarContentView(appModel: appModel)
        } label: {
            Image(nsImage: TypeMoreMenuBarIconFactory.image(for: appModel.sessionState))
        }

        Settings {
            SettingsView(appModel: appModel)
                .frame(width: 620, height: 480)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
