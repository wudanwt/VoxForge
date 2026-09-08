import Foundation

struct DictionaryProcessingResult: Equatable {
    var text: String
    var appliedEntryIDs: [UUID]
    var replacementCount: Int
}

protocol PersonalDictionaryProcessing {
    func process(
        _ text: String,
        entries: [DictionaryEntry],
        targetBundleIdentifier: String
    ) -> DictionaryProcessingResult
}

struct PersonalDictionaryProcessor: PersonalDictionaryProcessing {
    private struct Rule {
        var entryID: UUID
        var alias: String
        var replacement: String
    }

    func process(
        _ text: String,
        entries: [DictionaryEntry],
        targetBundleIdentifier: String
    ) -> DictionaryProcessingResult {
        let rules = entries
            .filter { $0.isEnabled && $0.behavior == .fixed && $0.scope.includes(bundleIdentifier: targetBundleIdentifier) }
            .flatMap { entry in
                entry.aliases.map { Rule(entryID: entry.id, alias: $0, replacement: entry.term) }
            }
            .filter { !$0.alias.isEmpty && !$0.replacement.isEmpty }
            .sorted { $0.alias.count > $1.alias.count }

        guard !rules.isEmpty, !text.isEmpty else {
            return DictionaryProcessingResult(text: text, appliedEntryIDs: [], replacementCount: 0)
        }

        var output = ""
        var index = text.startIndex
        var appliedIDs: [UUID] = []
        var replacementCount = 0

        while index < text.endIndex {
            if let match = rules.lazy.compactMap({ rule -> (Rule, Range<String.Index>)? in
                guard let range = text.range(
                    of: rule.alias,
                    options: [.anchored, .caseInsensitive, .widthInsensitive],
                    range: index..<text.endIndex
                ), hasValidWordBoundaries(in: text, range: range, alias: rule.alias) else {
                    return nil
                }
                return (rule, range)
            }).first {
                output.append(match.0.replacement)
                index = match.1.upperBound
                replacementCount += 1
                if !appliedIDs.contains(match.0.entryID) {
                    appliedIDs.append(match.0.entryID)
                }
            } else {
                output.append(text[index])
                index = text.index(after: index)
            }
        }

        return DictionaryProcessingResult(text: output, appliedEntryIDs: appliedIDs, replacementCount: replacementCount)
    }

    private func hasValidWordBoundaries(in text: String, range: Range<String.Index>, alias: String) -> Bool {
        guard let first = alias.first, let last = alias.last else { return false }
        if isWordCharacter(first), range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            if isWordCharacter(previous) { return false }
        }
        if isWordCharacter(last), range.upperBound < text.endIndex, isWordCharacter(text[range.upperBound]) {
            return false
        }
        return true
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            $0.isASCII && CharacterSet.alphanumerics.contains($0)
        }
    }
}
