import Foundation

final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var dictationHotkey: HotkeyDefinition {
        get { hotkey(forKey: "dictationHotkey", fallback: .defaultDictation) }
        set { setHotkey(newValue, forKey: "dictationHotkey") }
    }

    var returnHotkey: HotkeyDefinition {
        get { hotkey(forKey: "returnHotkey", fallback: .defaultReturn) }
        set { setHotkey(newValue, forKey: "returnHotkey") }
    }

    var selectedMode: DictationMode {
        get {
            guard let rawValue = defaults.string(forKey: "selectedMode") else { return .codingPrompt }
            return DictationMode(rawValue: rawValue) ?? .codingPrompt
        }
        set {
            defaults.set(newValue.rawValue, forKey: "selectedMode")
        }
    }

    var transcriptionLanguage: TranscriptionLanguage {
        get {
            guard let rawValue = defaults.string(forKey: "transcriptionLanguage") else { return .chinese }
            return TranscriptionLanguage(rawValue: rawValue) ?? .chinese
        }
        set {
            defaults.set(newValue.rawValue, forKey: "transcriptionLanguage")
        }
    }

    var recognitionBackend: RecognitionBackend {
        get {
            guard let rawValue = defaults.string(forKey: "recognitionBackend") else { return .sherpaParaformer }
            let backend = RecognitionBackend(rawValue: rawValue) ?? .sherpaParaformer
            if backend == .appleDictation {
                defaults.set(RecognitionBackend.sherpaParaformer.rawValue, forKey: "recognitionBackend")
                return .sherpaParaformer
            }
            return backend
        }
        set {
            defaults.set(newValue.rawValue, forKey: "recognitionBackend")
        }
    }

    var whisperKitStreamingModel: String {
        get { defaults.string(forKey: "whisperKitStreamingModel") ?? "small" }
        set { defaults.set(newValue, forKey: "whisperKitStreamingModel") }
    }

    var saveHistory: Bool {
        get {
            if defaults.object(forKey: "saveHistory") == nil { return true }
            return defaults.bool(forKey: "saveHistory")
        }
        set {
            defaults.set(newValue, forKey: "saveHistory")
        }
    }

    var llmOptimizationEnabled: Bool {
        get { defaults.bool(forKey: "llmOptimizationEnabled") }
        set { defaults.set(newValue, forKey: "llmOptimizationEnabled") }
    }

    var llmBaseURL: String {
        get { defaults.string(forKey: "llmBaseURL") ?? "https://api.openai.com/v1" }
        set { defaults.set(newValue, forKey: "llmBaseURL") }
    }

    var llmModel: String {
        get { defaults.string(forKey: "llmModel") ?? "gpt-4.1-mini" }
        set { defaults.set(newValue, forKey: "llmModel") }
    }

    var llmStyleInstruction: String {
        get { defaults.string(forKey: "llmStyleInstruction") ?? "直接可发送的编程提示词" }
        set { defaults.set(newValue, forKey: "llmStyleInstruction") }
    }

    var llmCustomPrompt: String {
        get { defaults.string(forKey: "llmCustomPrompt") ?? "" }
        set { defaults.set(newValue, forKey: "llmCustomPrompt") }
    }

    var keepDebugRecordings: Bool {
        get { defaults.bool(forKey: "keepDebugRecordings") }
        set { defaults.set(newValue, forKey: "keepDebugRecordings") }
    }

    var externalTriggerEnabled: Bool {
        get { defaults.bool(forKey: "externalTriggerEnabled") }
        set { defaults.set(newValue, forKey: "externalTriggerEnabled") }
    }

    var externalTriggerVendorID: Int {
        get {
            let value = defaults.integer(forKey: "externalTriggerVendorID")
            return value == 0 ? 11427 : value
        }
        set { defaults.set(newValue, forKey: "externalTriggerVendorID") }
    }

    var externalTriggerProductID: Int {
        get {
            let value = defaults.integer(forKey: "externalTriggerProductID")
            return value == 0 ? 16401 : value
        }
        set { defaults.set(newValue, forKey: "externalTriggerProductID") }
    }

    var externalTriggerSuppressVolume: Bool {
        get {
            if defaults.object(forKey: "externalTriggerSuppressVolume") == nil { return true }
            return defaults.bool(forKey: "externalTriggerSuppressVolume")
        }
        set { defaults.set(newValue, forKey: "externalTriggerSuppressVolume") }
    }

    var externalTriggerCancelModifier: ExternalTriggerCancelModifier {
        get {
            guard let value = defaults.string(forKey: "externalTriggerCancelModifier") else { return .control }
            return ExternalTriggerCancelModifier(rawValue: value) ?? .control
        }
        set { defaults.set(newValue.rawValue, forKey: "externalTriggerCancelModifier") }
    }

    private func hotkey(forKey key: String, fallback: HotkeyDefinition) -> HotkeyDefinition {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(HotkeyDefinition.self, from: data),
              value.isValidGlobalShortcut
        else {
            return fallback
        }
        return value
    }

    private func setHotkey(_ hotkey: HotkeyDefinition, forKey key: String) {
        guard let data = try? JSONEncoder().encode(hotkey) else { return }
        defaults.set(data, forKey: key)
    }
}
