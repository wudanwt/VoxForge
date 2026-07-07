import Foundation

enum HistoryRetention: String, CaseIterable, Identifiable, Codable {
    case forever
    case thirtyDays
    case sevenDays
    case oneDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever:
            "永久"
        case .thirtyDays:
            "30 天"
        case .sevenDays:
            "7 天"
        case .oneDay:
            "1 天"
        }
    }

    var cutoffDate: Date? {
        let interval: TimeInterval
        switch self {
        case .forever:
            return nil
        case .thirtyDays:
            interval = 30 * 24 * 60 * 60
        case .sevenDays:
            interval = 7 * 24 * 60 * 60
        case .oneDay:
            interval = 24 * 60 * 60
        }
        return Date().addingTimeInterval(-interval)
    }
}
