import Foundation

struct TranscriptRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var rawText: String
    var modeRawValue: String
    var targetApplicationName: String
    var targetBundleIdentifier: String
    var createdAt: Date
    var duration: TimeInterval
    var inserted: Bool
    var optimizedWithLLM: Bool

    init(
        id: UUID = UUID(),
        text: String,
        rawText: String,
        mode: DictationMode,
        targetApplicationName: String,
        targetBundleIdentifier: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        inserted: Bool,
        optimizedWithLLM: Bool = false
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.modeRawValue = mode.rawValue
        self.targetApplicationName = targetApplicationName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.createdAt = createdAt
        self.duration = duration
        self.inserted = inserted
        self.optimizedWithLLM = optimizedWithLLM
    }

    var mode: DictationMode {
        DictationMode(rawValue: modeRawValue) ?? .codingPrompt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case rawText
        case modeRawValue
        case targetApplicationName
        case targetBundleIdentifier
        case createdAt
        case duration
        case inserted
        case optimizedWithLLM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        rawText = try container.decode(String.self, forKey: .rawText)
        modeRawValue = try container.decode(String.self, forKey: .modeRawValue)
        targetApplicationName = try container.decode(String.self, forKey: .targetApplicationName)
        targetBundleIdentifier = try container.decode(String.self, forKey: .targetBundleIdentifier)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        inserted = try container.decode(Bool.self, forKey: .inserted)
        optimizedWithLLM = try container.decodeIfPresent(Bool.self, forKey: .optimizedWithLLM) ?? false
    }
}
