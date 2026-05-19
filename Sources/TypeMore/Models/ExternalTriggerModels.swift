import AppKit
import Foundation

struct ExternalTriggerDevice: Identifiable, Hashable {
    enum SourceType: String, Hashable {
        case hid = "HID"
        case audioInput = "音频输入"
    }

    var id: String { "\(sourceType.rawValue)-\(name)-\(vendorID ?? -1)-\(productID ?? -1)-\(transport)" }
    var name: String
    var vendorID: Int?
    var productID: Int?
    var transport: String
    var sourceType: SourceType
    var isMatched: Bool

    var vendorDisplay: String { vendorID.map(String.init) ?? "-" }
    var productDisplay: String { productID.map(String.init) ?? "-" }
}

enum ExternalTriggerStatus: Hashable {
    case disabled
    case notDetected
    case connected
    case listening
    case permissionMissing
    case suppressUnavailable

    var title: String {
        switch self {
        case .disabled: "未启用"
        case .notDetected: "未检测到"
        case .connected: "已连接"
        case .listening: "监听中"
        case .permissionMissing: "缺少权限"
        case .suppressUnavailable: "无法阻止音量事件"
        }
    }
}

enum ExternalTriggerEventType: String, Hashable {
    case volumeIncrement = "volume_increment"
    case singleClick = "single_click"
    case modifierClickCancel = "modifier_click_cancel"
    case suppressedVolumeIncrement = "suppressed_volume_increment"
}

struct ExternalTriggerLastEvent: Hashable {
    var type: ExternalTriggerEventType
    var date: Date
    var suppressed: Bool

    var summary: String {
        "\(type.rawValue) · \(date.formatted(date: .omitted, time: .standard)) · \(suppressed ? "已阻止音量" : "未阻止音量")"
    }
}

enum ExternalTriggerCancelModifier: String, CaseIterable, Identifiable {
    case control
    case option
    case command
    case shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control: "Ctrl"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        }
    }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control: .control
        case .option: .option
        case .command: .command
        case .shift: .shift
        }
    }
}
