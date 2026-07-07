import AppKit
import Foundation

final class PasteboardTextInsertionService: TextInsertionService {
    func insert(_ text: String, targetBundleIdentifier: String?) async throws {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedChangeCount = pasteboard.changeCount

        try await activateTargetApp(bundleIdentifier: targetBundleIdentifier, timeout: 1.5)
        sendCommandV()

        try? await Task.sleep(nanoseconds: 500_000_000)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let pasteboard = NSPasteboard.general
            guard Self.shouldRestorePasteboard(recordedChangeCount: insertedChangeCount, currentChangeCount: pasteboard.changeCount) else {
                return
            }
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    func sendReturn(targetBundleIdentifier: String?) async throws {
        try await activateTargetApp(bundleIdentifier: targetBundleIdentifier, timeout: 1.5)
        sendKey(keyCode: 36, flags: [])
    }

    static func shouldRestorePasteboard(recordedChangeCount: Int, currentChangeCount: Int) -> Bool {
        recordedChangeCount == currentChangeCount
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

    private func activateTargetApp(bundleIdentifier: String?, timeout: TimeInterval) async throws {
        let appBundleIdentifier = Bundle.main.bundleIdentifier
        let shouldHideSelf = await MainActor.run {
            NSApp.isActive || bundleIdentifier == nil || bundleIdentifier == appBundleIdentifier || bundleIdentifier == RunningApplicationInfo.generic.bundleIdentifier
        }
        if shouldHideSelf {
            await MainActor.run {
                NSApp.hide(nil)
            }
        }

        guard let bundleIdentifier,
              bundleIdentifier != appBundleIdentifier,
              bundleIdentifier != RunningApplicationInfo.generic.bundleIdentifier
        else {
            try? await Task.sleep(nanoseconds: 180_000_000)
            return
        }

        let target = await MainActor.run {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first
        }
        guard let target else {
            throw TypeMoreError.targetActivationFailed(bundleIdentifier)
        }
        _ = await MainActor.run {
            target.activate(options: [.activateAllWindows])
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let frontmostBundleIdentifier = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
            if frontmostBundleIdentifier == bundleIdentifier {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw TypeMoreError.targetActivationFailed(target.localizedName ?? bundleIdentifier)
    }
}
