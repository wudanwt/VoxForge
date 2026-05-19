import Foundation

enum TranscriptionLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case chinese
    case auto
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese:
            "中文优先"
        case .auto:
            "自动检测"
        case .english:
            "英文"
        }
    }

    var whisperLanguageCode: String? {
        switch self {
        case .chinese:
            "zh"
        case .auto:
            nil
        case .english:
            "en"
        }
    }

    var shouldDetectLanguage: Bool {
        self == .auto
    }
}
