// AIReplyVariant.swift
// OSGKeyboard · Shared
//
// Typed reply choices produced by one clipboard-reply request. Model output
// never controls SF Symbols or display labels; only these local allowlists do.

import Foundation

public struct AIReplyVariant: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case ordinary
        case formal
        case playful
        case invitationAccept
        case invitationDecline
        case invitationTentative
        case taskAcknowledge
        case taskClarify
        case taskNegotiate
        case blessingReturn
        case blessingWarm
        case blessingPlayful
        case clarificationDirect
        case clarificationQuestion
        case clarificationConfirm

        public var systemImage: String {
            switch self {
            case .ordinary:
                return "bubble.left.fill"
            case .formal:
                return "briefcase.fill"
            case .playful:
                return "theatermasks.fill"
            case .invitationAccept, .taskAcknowledge:
                return "checkmark.circle.fill"
            case .invitationDecline:
                return "hand.raised.fill"
            case .invitationTentative:
                return "clock.fill"
            case .taskClarify, .clarificationQuestion:
                return "questionmark.bubble.fill"
            case .taskNegotiate:
                return "arrow.left.arrow.right"
            case .blessingReturn:
                return "heart.fill"
            case .blessingWarm:
                return "hands.sparkles.fill"
            case .blessingPlayful:
                return "party.popper.fill"
            case .clarificationDirect:
                return "bubble.left.and.text.bubble.right.fill"
            case .clarificationConfirm:
                return "checkmark.bubble.fill"
            }
        }

        public var titleKey: String {
            switch self {
            case .ordinary:
                return "keyboard.ai.replyVariant.ordinary"
            case .formal:
                return "keyboard.ai.replyVariant.formal"
            case .playful:
                return "keyboard.ai.replyVariant.playful"
            case .invitationAccept:
                return "keyboard.ai.replyVariant.invitationAccept"
            case .invitationDecline:
                return "keyboard.ai.replyVariant.invitationDecline"
            case .invitationTentative:
                return "keyboard.ai.replyVariant.invitationTentative"
            case .taskAcknowledge:
                return "keyboard.ai.replyVariant.taskAcknowledge"
            case .taskClarify:
                return "keyboard.ai.replyVariant.taskClarify"
            case .taskNegotiate:
                return "keyboard.ai.replyVariant.taskNegotiate"
            case .blessingReturn:
                return "keyboard.ai.replyVariant.blessingReturn"
            case .blessingWarm:
                return "keyboard.ai.replyVariant.blessingWarm"
            case .blessingPlayful:
                return "keyboard.ai.replyVariant.blessingPlayful"
            case .clarificationDirect:
                return "keyboard.ai.replyVariant.clarificationDirect"
            case .clarificationQuestion:
                return "keyboard.ai.replyVariant.clarificationQuestion"
            case .clarificationConfirm:
                return "keyboard.ai.replyVariant.clarificationConfirm"
            }
        }

        /// Generic choices communicate tone through emotion icons. Intent
        /// choices keep their fixed icon so the user's decision stays clear.
        public var usesEmotionIcon: Bool {
            switch self {
            case .ordinary, .formal, .playful:
                return true
            case .invitationAccept,
                 .invitationDecline,
                 .invitationTentative,
                 .taskAcknowledge,
                 .taskClarify,
                 .taskNegotiate,
                 .blessingReturn,
                 .blessingWarm,
                 .blessingPlayful,
                 .clarificationDirect,
                 .clarificationQuestion,
                 .clarificationConfirm:
                return false
            }
        }
    }

    /// A bounded semantic hint for future feedback and presentation work.
    /// Unknown model values are intentionally normalized to `.neutral`.
    public enum Emotion: String, CaseIterable, Sendable {
        case neutral
        case warm
        case celebratory
        case empathetic
        case encouraging
        case grateful
        case apologetic
        case reassuring
        case playful
        case enthusiastic
        case calm

        /// The model selects only this semantic enum. SF Symbol names stay
        /// local and validated so malformed model output cannot control UI.
        public func systemImage(fallback kind: Kind) -> String {
            switch self {
            case .neutral:
                return kind.systemImage
            case .warm, .grateful:
                return "heart.fill"
            case .celebratory:
                return "party.popper.fill"
            case .empathetic:
                return "heart.text.square.fill"
            case .encouraging:
                return "hand.thumbsup.fill"
            case .apologetic:
                return "exclamationmark.bubble.fill"
            case .reassuring:
                return "checkmark.shield.fill"
            case .playful:
                return "theatermasks.fill"
            case .enthusiastic:
                return "sparkles"
            case .calm:
                return "leaf.fill"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let emotion: Emotion
    public let text: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        emotion: Emotion,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.emotion = emotion
        self.text = text
    }
}

public enum AIReplyVariantSet: String, CaseIterable, Sendable {
    case generic
    case invitation
    case task
    case blessing
    case clarification

    public var kinds: [AIReplyVariant.Kind] {
        switch self {
        case .generic:
            return [.ordinary, .formal, .playful]
        case .invitation:
            return [.invitationAccept, .invitationDecline, .invitationTentative]
        case .task:
            return [.taskAcknowledge, .taskClarify, .taskNegotiate]
        case .blessing:
            return [.blessingReturn, .blessingWarm, .blessingPlayful]
        case .clarification:
            return [
                .clarificationDirect,
                .clarificationQuestion,
                .clarificationConfirm
            ]
        }
    }

    public static func resolve(scene: AIClipboardReplyScene?) -> Self {
        switch scene {
        case .invitation:
            return .invitation
        case .task:
            return .task
        case .blessing:
            return .blessing
        case .clarification:
            return .clarification
        case .complaint, .negativeQuestion, nil:
            return .generic
        }
    }

    public static func resolve(kinds: Set<AIReplyVariant.Kind>) -> Self? {
        allCases.first { Set($0.kinds) == kinds }
    }

    public static func shouldGenerate(
        multipleRepliesEnabled: Bool,
        scene: AIClipboardReplyScene?
    ) -> Bool {
        multipleRepliesEnabled || scene?.requiresIntentVariants == true
    }
}

public enum AIReplyVariantParsingResult: Equatable, Sendable {
    case variants([AIReplyVariant])
    case single(AIReplyVariant)
}

public enum AIReplyVariantParser {
    /// The only accepted multi-reply wire shape is:
    /// `{"variants":[{"kind":"ordinary","emotion":"warm","text":"…"}, ...]}`
    /// with exactly one item of each kind and no additional JSON fields.
    public static func parse(
        _ raw: String,
        sourceText: String? = nil,
        variantSet: AIReplyVariantSet = .generic
    ) -> [AIReplyVariant]? {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              Set(object.keys) == ["variants"],
              let items = object["variants"] as? [[String: Any]],
              items.count == variantSet.kinds.count else {
            return nil
        }

        let expectedKinds = Set(variantSet.kinds)
        var variantsByKind: [AIReplyVariant.Kind: AIReplyVariant] = [:]
        for item in items {
            guard Set(item.keys) == ["kind", "emotion", "text"],
                  let rawKind = item["kind"] as? String,
                  let kind = AIReplyVariant.Kind(rawValue: rawKind),
                  expectedKinds.contains(kind),
                  variantsByKind[kind] == nil,
                  let rawEmotion = item["emotion"] as? String,
                  let rawText = item["text"] as? String else {
                return nil
            }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  !isSourceEcho(text, sourceText: sourceText) else {
                return nil
            }
            let emotion = AIReplyVariant.Emotion(rawValue: rawEmotion) ?? .neutral
            variantsByKind[kind] = AIReplyVariant(
                kind: kind,
                emotion: emotion,
                text: text
            )
        }

        let ordered = variantSet.kinds.compactMap { variantsByKind[$0] }
        return ordered.count == variantSet.kinds.count ? ordered : nil
    }

    /// Strict multi-reply parsing with a conservative single ordinary fallback
    /// only for generic tone choices. Intent scenes fail closed instead.
    public static func parseOrFallback(
        _ raw: String,
        sourceText: String? = nil,
        variantSet: AIReplyVariantSet = .generic
    ) -> AIReplyVariantParsingResult? {
        if let variants = parse(
            raw,
            sourceText: sourceText,
            variantSet: variantSet
        ) {
            return .variants(variants)
        }
        // A plain-text fallback cannot safely preserve the user's intended
        // stance for invitation, task, blessing, or clarification choices.
        guard variantSet == .generic else { return nil }
        guard let text = fallbackText(from: raw),
              !isSourceEcho(text, sourceText: sourceText) else {
            return nil
        }
        return .single(
            AIReplyVariant(kind: .ordinary, emotion: .neutral, text: text)
        )
    }

    public static func fallbackText(from raw: String) -> String? {
        let unfenced = removingCodeFence(from: raw)
        guard !unfenced.isEmpty else { return nil }

        if let data = unfenced.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let extracted = replyText(in: json) {
            return normalized(extracted)
        }
        if let extracted = textValueFromMalformedJSON(unfenced) {
            return normalized(extracted)
        }

        guard !looksLikeJSON(unfenced) else { return nil }
        return normalized(unfenced)
    }

    private static let preferredTextKeys = [
        "text", "reply", "response", "content", "message", "answer"
    ]

    private static let metadataValues = Set(
        AIReplyVariant.Kind.allCases.map(\.rawValue)
            + AIReplyVariant.Emotion.allCases.map(\.rawValue)
            + ["variants", "kind", "emotion", "text"]
    )

    /// Rejects responses that merely report the clipboard message back to its
    /// sender. A bounded LCS catches close paraphrases while still allowing a
    /// reply to mention a necessary name or short keyword.
    private static func isSourceEcho(
        _ candidate: String,
        sourceText: String?
    ) -> Bool {
        guard let sourceText else { return false }
        let source = normalizedComparisonCharacters(sourceText)
        let reply = normalizedComparisonCharacters(candidate)
        guard source.count >= 8, reply.count >= 8 else { return false }

        let overlap = longestCommonSubsequenceLength(source, reply)
        guard overlap >= 8 else { return false }
        return Double(overlap) / Double(source.count) >= 0.68
            && Double(overlap) / Double(reply.count) >= 0.45
    }

    private static func normalizedComparisonCharacters(
        _ text: String
    ) -> [Character] {
        Array(
            text.lowercased().filter { character in
                character.unicodeScalars.contains {
                    CharacterSet.alphanumerics.contains($0)
                }
            }.prefix(1_000)
        )
    }

    private static func longestCommonSubsequenceLength(
        _ lhs: [Character],
        _ rhs: [Character]
    ) -> Int {
        let shorter: [Character]
        let longer: [Character]
        if lhs.count <= rhs.count {
            shorter = lhs
            longer = rhs
        } else {
            shorter = rhs
            longer = lhs
        }
        var previous = Array(repeating: 0, count: shorter.count + 1)
        var current = previous
        for longCharacter in longer {
            for index in shorter.indices {
                if longCharacter == shorter[index] {
                    current[index + 1] = previous[index] + 1
                } else {
                    current[index + 1] = max(
                        previous[index + 1],
                        current[index]
                    )
                }
            }
            swap(&previous, &current)
            current = Array(repeating: 0, count: shorter.count + 1)
        }
        return previous[shorter.count]
    }

    private static func replyText(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            for key in preferredTextKeys {
                if let text = object[key] as? String,
                   let normalized = normalized(text) {
                    return normalized
                }
            }
            for nested in object.values {
                if let text = replyText(in: nested) {
                    return text
                }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let text = replyText(in: nested) {
                    return text
                }
            }
        }
        if let text = value as? String,
           !metadataValues.contains(text),
           let normalized = normalized(text) {
            return normalized
        }
        return nil
    }

    private static func removingCodeFence(from raw: String) -> String {
        var lines = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textValueFromMalformedJSON(_ raw: String) -> String? {
        let keyPattern = #""(?:text|reply|response|content|message|answer)"\s*:\s*("(?:\\.|[^"\\])*")"#
        if let regex = try? NSRegularExpression(pattern: keyPattern),
           let match = regex.firstMatch(
               in: raw,
               range: NSRange(raw.startIndex..., in: raw)
           ),
           let range = Range(match.range(at: 1), in: raw) {
            return decodeJSONString(String(raw[range]))
        }

        let stringPattern = #""(?:\\.|[^"\\])*""#
        guard let regex = try? NSRegularExpression(pattern: stringPattern) else {
            return nil
        }
        let candidates = regex.matches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw)
        ).compactMap { match -> String? in
            guard let range = Range(match.range, in: raw),
                  let decoded = decodeJSONString(String(raw[range])),
                  !metadataValues.contains(decoded) else {
                return nil
            }
            return normalized(decoded)
        }
        return candidates.max { $0.count < $1.count }
    }

    private static func decodeJSONString(_ quoted: String) -> String? {
        guard let data = quoted.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func looksLikeJSON(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private static func normalized(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
