import Foundation

enum ApplicationOperatingMode: String, CaseIterable, Identifiable {
    case fullDictation
    case djiHotkeyBridge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullDictation:
            "完整听写应用"
        case .djiHotkeyBridge:
            "仅 DJI 快捷键桥接"
        }
    }

    var description: String {
        switch self {
        case .fullDictation:
            "使用 VoxForge 的录音、语音识别、文本优化和自动输入能力。"
        case .djiHotkeyBridge:
            "只监听 DJI Mic 按钮并向系统发送目标组合键，不启动录音或语音模型。"
        }
    }
}

enum BridgeClickStep: String, Equatable {
    case startDictation
    case stopDictation
    case sendReturn

    var nextActionTitle: String {
        switch self {
        case .startDictation:
            "第 1 次：开始外部听写"
        case .stopDictation:
            "第 2 次：结束外部听写"
        case .sendReturn:
            "第 3 次：发送回车"
        }
    }
}
