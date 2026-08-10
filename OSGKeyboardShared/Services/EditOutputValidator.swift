// EditOutputValidator.swift
// OSGKeyboard · Shared

import Foundation

public enum EditOutputValidationError: Error, Equatable, Sendable {
    case empty
    case unchanged
    case protocolLeak
    case excessiveExpansion
}

public enum EditOutputValidator {
    public static func validate(
        sourceText: String,
        output: String
    ) -> Result<String, EditOutputValidationError> {
        let source = normalized(sourceText)
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return .failure(.empty) }
        guard normalized(result) != source else { return .failure(.unchanged) }

        let lowered = result.lowercased()
        let leaks = [
            "<edit_request",
            "<source_text",
            "<spoken_instruction",
            "edit-last-input-v1",
            "highest-priority rules",
            "最高优先级规则"
        ]
        guard !leaks.contains(where: lowered.contains) else {
            return .failure(.protocolLeak)
        }

        let expansionLimit = max(sourceText.count * 2, sourceText.count + 800)
        guard result.count <= expansionLimit else {
            return .failure(.excessiveExpansion)
        }
        return .success(result)
    }

    private static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
    }
}
