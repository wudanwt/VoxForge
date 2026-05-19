import AppKit
import Foundation

final class PasteboardTextInsertionService: TextInsertionService {
    func insert(_ text: String, targetBundleIdentifier: String?) async throws {
        activateTargetApp(bundleIdentifier: targetBundleIdentifier)
        try? await Task.sleep(nanoseconds: 350_000_000)

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendCommandV()

        try? await Task.sleep(nanoseconds: 500_000_000)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    func sendReturn() throws {
        sendKey(keyCode: 36, flags: [])
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        commandDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        commandUp?.flags = []

        [commandDown, vDown, vUp, commandUp].forEach { event in
            event?.post(tap: .cghidEventTap)
        }
    }

    private func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func activateTargetApp(bundleIdentifier: String?) {
        guard let bundleIdentifier, bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        NSApp.hide(nil)
        let target = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first
        target?.activate(options: [.activateAllWindows])
    }
}
