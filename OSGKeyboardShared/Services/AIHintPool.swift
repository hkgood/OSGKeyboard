// AIHintPool.swift
// OSGKeyboard · Shared
//
// Builds the idle carousel pool from local + remote cards. Clipboard
// sentence cards are excluded: the 30s copy window shows skill chips.

import Foundation

public enum AIHintPool: Sendable {
    public static func activeCards(
        pack: AIHintPack
    ) -> [AIHintCard] {
        let regularCards = pack.cards.filter { !$0.requiresClipboard30s }
            .filter { !isHistoricalToday($0) }

        // Clipboard-conditioned sentences no longer rotate in the carousel;
        // the 30s window shows skill chips instead. Keep evergreen content
        // loaded so leaving the window does not flash a leftover clipboard card.
        var merged = regularCards
        let localRegular = AIHintLocalCatalog.cards(locale: pack.locale)
            .filter { !$0.requiresClipboard30s }
        for card in localRegular where !merged.contains(where: { $0.id == card.id }) {
            merged.append(card)
        }
        return merged.sorted { $0.priority > $1.priority }
    }

    /// Copy-then-30s window where clipboard skill chips replace the carousel.
    public static func isClipboardSkillWindowActive(
        clipboardHistoryEnabled: Bool,
        newestClipboard: ClipboardHistoryEntry?,
        now: Date = Date()
    ) -> Bool {
        clipboardHistoryEnabled
            && newestClipboard.map { ClipboardHistoryPolicy.isEligibleForAIHint($0, now: now) } == true
    }

    /// Prompt for a tapped card. Clipboard cards fail closed so an expired
    /// window can never send an instruction without its material.
    public static func resolvePrompt(
        for card: AIHintCard,
        clipboardText: String?
    ) -> AIClipboardPrompt.Resolution {
        guard card.requiresClipboard30s else {
            return .ready(AIClipboardPrompt.strippingPlaceholder(card.prompt))
        }
        return AIClipboardPrompt.resolve(
            instruction: card.prompt,
            material: clipboardText
        )
    }

    private static func isHistoricalToday(_ card: AIHintCard) -> Bool {
        let haystack = (card.displayText + " " + card.prompt)
        return haystack.contains("历史上的今天") || haystack.localizedCaseInsensitiveContains("on this day")
    }
}

/// Shuffle-bag rotator for the idle carousel.
public struct AIHintCarouselBag: Sendable {
    private var bag: [AIHintCard] = []
    private var sourceFingerprint: Int = 0

    public init() {}

    public mutating func next(from cards: [AIHintCard]) -> AIHintCard? {
        guard !cards.isEmpty else { return nil }
        let fingerprint = cards.map(\.id).joined(separator: "|").hashValue
        if bag.isEmpty || fingerprint != sourceFingerprint {
            sourceFingerprint = fingerprint
            bag = cards.shuffled()
        }
        if bag.isEmpty { return nil }
        return bag.removeFirst()
    }

    public mutating func reset() {
        bag = []
        sourceFingerprint = 0
    }
}
