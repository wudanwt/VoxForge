import Foundation

struct AppProfile: Identifiable, Codable, Hashable {
    var id: String { bundleIdentifier }
    var displayName: String
    var bundleIdentifier: String
    var defaultMode: DictationMode
    var languageHint: String
    var submitKey: SubmitKey
    var readsForegroundContext: Bool

    static let generic = AppProfile(
        displayName: "Generic App",
        bundleIdentifier: "*",
        defaultMode: .codingPrompt,
        languageHint: "Auto",
        submitKey: .returnKey,
        readsForegroundContext: false
    )

    static let defaults: [AppProfile] = [
        AppProfile(displayName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", defaultMode: .codingPrompt, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: true),
        AppProfile(displayName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", defaultMode: .codingPrompt, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: true),
        AppProfile(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal", defaultMode: .literal, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: false),
        AppProfile(displayName: "iTerm", bundleIdentifier: "com.googlecode.iterm2", defaultMode: .literal, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: false),
        AppProfile(displayName: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop", defaultMode: .codingPrompt, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: true),
        AppProfile(displayName: "Safari", bundleIdentifier: "com.apple.Safari", defaultMode: .general, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: false),
        AppProfile(displayName: "Chrome", bundleIdentifier: "com.google.Chrome", defaultMode: .general, languageHint: "Auto", submitKey: .returnKey, readsForegroundContext: false),
        generic
    ]
}

enum SubmitKey: String, Codable, CaseIterable, Identifiable {
    case returnKey
    case commandReturn
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .returnKey: "Return"
        case .commandReturn: "Command + Return"
        case .none: "No submit key"
        }
    }
}
