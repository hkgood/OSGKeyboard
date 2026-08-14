// EnglishQWERTYProximity.swift
// OSGKeyboard · Shared
//
// Spatial cost for English autocorrect. Adjacent (including diagonal) keys
// are cheap; far substitutions are expensive. Inspired by AOSP LatinIME's
// proximity weighting — formula only, no Android code.

import Foundation

public struct EnglishAlignment: Equatable, Sendable {
    /// Weighted edit cost. `0` means identical.
    public var cost: Int
    public var isTransposition: Bool
    public var isShortening: Bool
}

public enum EnglishQWERTYProximity: Sendable {
    /// Two adjacent substitutions, or one farther miss, still eligible.
    public static let maxAutocorrectCost = 34
    public static let adjacentCost = 10
    public static let nearCost = 22
    public static let farCost = 34
    public static let insDelCost = 18
    public static let transpositionCost = 10

    /// US QWERTY, staggered rows matching the on-screen letter grid.
    private static let coordinates: [Character: (x: Double, y: Double)] = {
        let rows: [[Character]] = [
            Array("qwertyuiop"),
            Array("asdfghjkl"),
            Array("zxcvbnm")
        ]
        let offsets: [Double] = [0, 0.5, 1.5]
        var map: [Character: (x: Double, y: Double)] = [:]
        for (rowIndex, row) in rows.enumerated() {
            let origin = offsets[rowIndex]
            for (column, letter) in row.enumerated() {
                map[letter] = (origin + Double(column), Double(rowIndex))
            }
        }
        return map
    }()

    public static func neighbors(of letter: Character, includingSelf: Bool) -> [Character] {
        let needle = Character(letter.lowercased())
        guard let origin = coordinates[needle] else {
            return includingSelf ? [needle] : []
        }
        var hits: [Character] = []
        for (candidate, point) in coordinates {
            let distance = chebyshev(origin, point)
            if distance == 0 {
                if includingSelf { hits.append(candidate) }
            } else if distance <= 1.01 {
                hits.append(candidate)
            }
        }
        return hits
    }

    public static func keyDistance(_ a: Character, _ b: Character) -> Int {
        let left = Character(a.lowercased())
        let right = Character(b.lowercased())
        if left == right { return 0 }
        guard let origin = coordinates[left], let other = coordinates[right] else {
            return farCost
        }
        let distance = chebyshev(origin, other)
        if distance <= 1.01 { return adjacentCost }
        if distance <= 2.01 { return nearCost }
        return farCost
    }

    public static func align(typed: String, candidate: String) -> EnglishAlignment? {
        let source = asciiLowered(typed)
        let targetBytes = asciiLowered(candidate)
        return targetBytes.withUnsafeBufferPointer { pointer in
            align(typedASCII: source, candidateASCII: pointer)
        }
    }

    /// Same cost model as `align(typed:candidate:)`, but the candidate stays in
    /// a mapped file — no Swift `String` per scanned word.
    public static func align(
        typedASCII: [UInt8],
        candidateASCII: UnsafeBufferPointer<UInt8>
    ) -> EnglishAlignment? {
        let source = typedASCII
        let target = candidateASCII
        let delta = abs(source.count - target.count)
        guard delta <= 2 else { return nil }
        if delta == 0, bytesEqual(source, target) {
            return EnglishAlignment(cost: 0, isTransposition: false, isShortening: false)
        }

        if source.count == target.count, isAdjacentTransposition(source, target) {
            return EnglishAlignment(
                cost: transpositionCost,
                isTransposition: true,
                isShortening: false
            )
        }

        if source.count == target.count {
            var cost = 0
            for index in source.indices {
                cost += keyDistance(source[index], target[index])
                if cost > maxAutocorrectCost { return nil }
            }
            return EnglishAlignment(
                cost: cost,
                isTransposition: false,
                isShortening: false
            )
        }

        let cost = bandedEditCost(source, target)
        guard cost <= maxAutocorrectCost else { return nil }
        return EnglishAlignment(
            cost: cost,
            isTransposition: false,
            isShortening: target.count < source.count
        )
    }

    private static func keyDistance(_ a: UInt8, _ b: UInt8) -> Int {
        if a == b { return 0 }
        guard a >= 97, a <= 122, b >= 97, b <= 122 else { return farCost }
        return keyDistance(Character(UnicodeScalar(a)), Character(UnicodeScalar(b)))
    }

    private static func isAdjacentTransposition(
        _ source: [UInt8],
        _ target: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        guard source.count == target.count, source.count >= 2 else { return false }
        var mismatch = -1
        for index in source.indices where source[index] != target[index] {
            if mismatch == -1 {
                mismatch = index
            } else if index == mismatch + 1,
                      source[mismatch] == target[index],
                      source[index] == target[mismatch] {
                for rest in (index + 1)..<source.count where source[rest] != target[rest] {
                    return false
                }
                return true
            } else {
                return false
            }
        }
        return false
    }

    /// Banded Levenshtein with proximity substitutions and a Damerau swap.
    private static func bandedEditCost(
        _ source: [UInt8],
        _ target: UnsafeBufferPointer<UInt8>
    ) -> Int {
        let aCount = source.count
        let bCount = target.count
        var previous = Array(0...bCount).map { $0 * insDelCost }
        var older = previous
        for i in 1...aCount {
            var current = [Int](repeating: 0, count: bCount + 1)
            current[0] = i * insDelCost
            var rowMin = current[0]
            for j in 1...bCount {
                let substitution = previous[j - 1] + keyDistance(source[i - 1], target[j - 1])
                var value = min(
                    previous[j] + insDelCost,
                    current[j - 1] + insDelCost,
                    substitution
                )
                if i > 1, j > 1,
                   source[i - 1] == target[j - 2],
                   source[i - 2] == target[j - 1] {
                    value = min(value, older[j - 2] + transpositionCost)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > maxAutocorrectCost { return maxAutocorrectCost + 1 }
            older = previous
            previous = current
        }
        return previous[bCount]
    }

    private static func asciiLowered(_ string: String) -> [UInt8] {
        string.utf8.map { byte in
            (byte >= 65 && byte <= 90) ? byte + 32 : byte
        }
    }

    private static func bytesEqual(_ source: [UInt8], _ target: UnsafeBufferPointer<UInt8>) -> Bool {
        guard source.count == target.count else { return false }
        for index in source.indices where source[index] != target[index] {
            return false
        }
        return true
    }

    private static func chebyshev(
        _ a: (x: Double, y: Double),
        _ b: (x: Double, y: Double)
    ) -> Double {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }
}
