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

    var cancelHotkey: HotkeyDefinition {
        get { hotkey(forKey: "cancelHotkey", fallback: .defaultCancel) }
        set { setHotkey(newValue, forKey: "cancelHotkey") }
    }

    var applicationOperatingMode: ApplicationOperatingMode {
        get {
            guard let rawValue = defaults.string(forKey: "applicationOperatingMode") else {
                return .fullDictation
            }
            return ApplicationOperatingMode(rawValue: rawValue) ?? .fullDictation
        }
        set {
            defaults.set(newValue.rawValue, forKey: "applicationOperatingMode")
        }
    }

    var bridgeTargetHotkey: HotkeyDefinition {
        get { hotkey(forKey: "bridgeTargetHotkey", fallback: dictationHotkey) }
        set { setHotkey(newValue, forKey: "bridgeTargetHotkey") }
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
            if backend == .appleDictation && !RecognitionBackend.isAppleDictationSupported {
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

    var historyRetention: HistoryRetention {
        get {
            guard let rawValue = defaults.string(forKey: "historyRetention") else { return .forever }
            return HistoryRetention(rawValue: rawValue) ?? .forever
        }
        set {
            defaults.set(newValue.rawValue, forKey: "historyRetention")
        }
    }

    var personalDictionary: [DictionaryEntry] {
        get {
            guard let data = defaults.data(forKey: "personalDictionary"),
                  let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
            else {
                defaults.set(2, forKey: "personalDictionarySchemaVersion")
                return DictionaryEntry.defaults
            }
            let migrated = migratePersonalDictionaryIfNeeded(entries)
            return Self.sanitizedDictionary(migrated)
        }
        set {
            let sanitized = Self.sanitizedDictionary(newValue)
            guard Self.dictionaryValidationError(in: sanitized) == nil,
                  let data = try? JSONEncoder().encode(sanitized) else { return }
            defaults.set(data, forKey: "personalDictionary")
            defaults.set(2, forKey: "personalDictionarySchemaVersion")
        }
    }

    func resetPersonalDictionary() {
        defaults.removeObject(forKey: "personalDictionary")
    }

    static func sanitizedDictionary(_ entries: [DictionaryEntry]) -> [DictionaryEntry] {
        var output: [DictionaryEntry] = []

        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let aliases = entry.aliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && dictionaryKey(for: $0) != dictionaryKey(for: term) }
                .reduce(into: [String]()) { result, alias in
                    guard !result.contains(where: { dictionaryKey(for: $0) == dictionaryKey(for: alias) }) else { return }
                    result.append(alias)
                }
            let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleIdentifiers = entry.scope.applicationBundleIdentifiers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, bundleIdentifier in
                    guard !result.contains(bundleIdentifier) else { return }
                    result.append(bundleIdentifier)
                }
            output.append(DictionaryEntry(
                id: entry.id,
                term: term,
                aliases: aliases,
                note: note,
                isEnabled: entry.isEnabled,
                behavior: entry.behavior,
                scope: DictionaryEntryScope(applicationBundleIdentifiers: bundleIdentifiers)
            ))
        }

        return output
    }

    private static func isLegacyDefaultEntry(_ entry: DictionaryEntry, normalizedTerm term: String) -> Bool {
        term.caseInsensitiveCompare("vibe coding") == .orderedSame
            && entry.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.isEmpty
            && entry.note.trimmingCharacters(in: .whitespacesAndNewlines) == "AI 编程工作流常用术语"
            && entry.isEnabled
    }

    static func dictionaryValidationError(in entries: [DictionaryEntry]) -> String? {
        let enabled = entries.filter { $0.isEnabled && !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for entry in enabled where entry.behavior == .fixed && entry.aliases.isEmpty {
            return "固定替换词条“\(entry.term)”至少需要一个常见误听"
        }

        for index in enabled.indices {
            let current = enabled[index]
            let currentTermKey = dictionaryKey(for: current.term)
            let currentAliasKeys = Set(current.aliases.map { dictionaryKey(for: $0) })
            for otherIndex in enabled.indices where otherIndex > index {
                let other = enabled[otherIndex]
                guard current.scope.overlaps(with: other.scope) else { continue }
                let otherTermKey = dictionaryKey(for: other.term)
                let otherAliasKeys = Set(other.aliases.map { dictionaryKey(for: $0) })
                if currentTermKey == otherTermKey {
                    return "标准词条“\(current.term)”重复"
                }
                if !currentAliasKeys.isDisjoint(with: otherAliasKeys)
                    || currentAliasKeys.contains(otherTermKey)
                    || otherAliasKeys.contains(currentTermKey) {
                    return "词条“\(current.term)”和“\(other.term)”存在重叠的标准词或常见误听"
                }
            }
        }
        return nil
    }

    private func migratePersonalDictionaryIfNeeded(_ entries: [DictionaryEntry]) -> [DictionaryEntry] {
        guard defaults.integer(forKey: "personalDictionarySchemaVersion") < 2 else { return entries }
        let migrated = entries.filter { entry in
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            return !Self.isLegacyDefaultEntry(entry, normalizedTerm: term)
        }
        if let data = try? JSONEncoder().encode(Self.sanitizedDictionary(migrated)) {
            defaults.set(data, forKey: "personalDictionary")
        }
        defaults.set(2, forKey: "personalDictionarySchemaVersion")
        return migrated
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

    func llmPromptTemplate(for mode: DictationMode) -> String {
        if let value = defaults.string(forKey: llmPromptTemplateKey(for: mode)) {
            return value
        }
        if mode == .codingPrompt {
            return llmCustomPrompt
        }
        return ""
    }

    func setLLMPromptTemplate(_ value: String, for mode: DictationMode) {
        defaults.set(value, forKey: llmPromptTemplateKey(for: mode))
        if mode == .codingPrompt {
            llmCustomPrompt = value
        }
    }

    func resetLLMPromptTemplate(for mode: DictationMode) {
        defaults.removeObject(forKey: llmPromptTemplateKey(for: mode))
        if mode == .codingPrompt {
            defaults.removeObject(forKey: "llmCustomPrompt")
        }
    }

    func resetAllLLMPromptTemplates() {
        DictationMode.allCases.forEach { resetLLMPromptTemplate(for: $0) }
    }

    var keepDebugRecordings: Bool {
        get { defaults.bool(forKey: "keepDebugRecordings") }
        set { defaults.set(newValue, forKey: "keepDebugRecordings") }
    }

    var diagnosticAudioRetentionPolicy: DiagnosticAudioRetentionPolicy {
        get {
            guard let rawValue = defaults.string(forKey: "diagnosticAudioRetentionPolicy") else {
                return .onFailure
            }
            return DiagnosticAudioRetentionPolicy(rawValue: rawValue) ?? .onFailure
        }
        set {
            defaults.set(newValue.rawValue, forKey: "diagnosticAudioRetentionPolicy")
        }
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

    private func llmPromptTemplateKey(for mode: DictationMode) -> String {
        "llmPrompt.\(mode.rawValue)"
    }

    private static func dictionaryKey(for value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
