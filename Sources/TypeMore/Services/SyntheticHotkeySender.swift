import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

protocol SyntheticHotkeySending {
    func send(_ hotkey: HotkeyDefinition) throws
}

enum SyntheticHotkeySenderError: LocalizedError {
    case accessibilityPermissionMissing
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "缺少辅助功能权限，无法发送目标快捷键。"
        case .eventCreationFailed:
            "无法创建目标快捷键事件。"
        }
    }
}

struct CGEventSyntheticHotkeySender: SyntheticHotkeySending {
    func send(_ hotkey: HotkeyDefinition) throws {
        guard AXIsProcessTrusted() else {
            throw SyntheticHotkeySenderError.accessibilityPermissionMissing
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(hotkey.keyCode),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(hotkey.keyCode),
                keyDown: false
              )
        else {
            throw SyntheticHotkeySenderError.eventCreationFailed
        }

        let flags = eventFlags(from: hotkey.modifiers)
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func eventFlags(from carbonModifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        return flags
    }
}
