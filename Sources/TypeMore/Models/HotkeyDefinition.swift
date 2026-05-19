import AppKit
import Carbon
import Foundation

struct HotkeyDefinition: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultDictation = HotkeyDefinition(keyCode: 2, modifiers: carbonModifiers(control: true, option: true))
    static let defaultReturn = HotkeyDefinition(keyCode: 36, modifiers: carbonModifiers(control: true, option: true))
    static let defaultCancel = HotkeyDefinition(keyCode: 53, modifiers: carbonModifiers(control: true, option: true))

    var displayName: String {
        "\(modifierDisplayName)\(keyDisplayName)"
    }

    var modifierDisplayName: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    var keyDisplayName: String {
        KeyCodeName.names[keyCode] ?? "按键 \(keyCode)"
    }

    var isValidGlobalShortcut: Bool {
        modifiers != 0
    }

    static func from(event: NSEvent) -> HotkeyDefinition? {
        guard event.keyCode != 53 else { return nil }
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        return HotkeyDefinition(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    func matches(event: NSEvent) -> Bool {
        keyCode == UInt32(event.keyCode) && modifiers == Self.carbonModifiers(from: event.modifierFlags)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        if normalized.contains(.control) { result |= UInt32(controlKey) }
        if normalized.contains(.option) { result |= UInt32(optionKey) }
        if normalized.contains(.shift) { result |= UInt32(shiftKey) }
        if normalized.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func carbonModifiers(control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false) -> UInt32 {
        var result: UInt32 = 0
        if control { result |= UInt32(controlKey) }
        if option { result |= UInt32(optionKey) }
        if shift { result |= UInt32(shiftKey) }
        if command { result |= UInt32(cmdKey) }
        return result
    }
}

enum HotkeyTarget: String, Identifiable {
    case dictation
    case returnKey
    case cancel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: "听写快捷键"
        case .returnKey: "回车快捷键"
        case .cancel: "中断快捷键"
        }
    }
}

struct HotkeyRegistrationResult: Hashable {
    var target: HotkeyTarget
    var hotkey: HotkeyDefinition
    var status: OSStatus

    var succeeded: Bool { status == noErr }

    static func message(for results: [HotkeyRegistrationResult]) -> String {
        let failures = results.filter { !$0.succeeded }
        if failures.isEmpty {
            return "快捷键已注册：\(results.map { $0.hotkey.displayName }.joined(separator: " / "))"
        }
        return failures.map { "\($0.target.title) 注册失败（\($0.status)）" }.joined(separator: "，")
    }
}

private enum KeyCodeName {
    static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        51: "⌫", 53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        118: "F4", 122: "F1", 120: "F2", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
