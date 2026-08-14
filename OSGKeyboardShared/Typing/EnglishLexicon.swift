// EnglishLexicon.swift
// OSGKeyboard · Shared
//
// Offline English word list + bigrams for the typing extension.
// The 40k-word table is a mmap'd binary (`english_lexicon.bin`); dirty heap
// stays near zero until a lookup materializes a handful of result strings.
// TSV files in the repo are the build input, not the runtime format.

import Foundation

public struct EnglishScoredCorrection: Equatable, Sendable {
    public var word: String
    public var spatialCost: Int
    public var frequency: Int
    public var isTransposition: Bool
    public var isShortening: Bool

    public init(
        word: String,
        spatialCost: Int,
        frequency: Int,
        isTransposition: Bool,
        isShortening: Bool
    ) {
        self.word = word
        self.spatialCost = spatialCost
        self.frequency = frequency
        self.isTransposition = isTransposition
        self.isShortening = isShortening
    }
}

/// Ranked English lexicon used by autocomplete / autocorrect / next-word.
public final class EnglishLexicon: @unchecked Sendable {
    public static let shared = EnglishLexicon()

    private var mapped: Data?
    private var header: FileHeader?
    private var loaded = false
    private let lock = NSLock()

    public init() {}

    /// True after a successful mmap. Tests use this to prove Chinese typing
    /// does not pull the English table into the extension.
    public var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loaded
    }

    public func prepare() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loadMappedLexicon()
    }

    /// Release the mapped file when leaving English / the typing surface.
    public func unload() {
        lock.lock()
        defer { lock.unlock() }
        mapped = nil
        header = nil
        loaded = false
    }

    public var wordCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return header?.unigramCount ?? 0
    }

    public func frequency(of word: String) -> Int {
        withMap { buf, header in
            guard let index = lookupIndex(asciiLowered(word), header: header, buf: buf) else {
                return 0
            }
            return frequency(at: index, header: header, buf: buf)
        } ?? 0
    }

    public func contains(_ word: String) -> Bool {
        withMap { buf, header in
            lookupIndex(asciiLowered(word), header: header, buf: buf) != nil
        } ?? false
    }

    /// Highest-frequency unigrams, for next-word fallback when no bigram hits.
    public func topWords(limit: Int = 6) -> [String] {
        guard limit > 0 else { return [] }
        return withMap { buf, header in
            let count = min(limit, header.unigramCount)
            var words: [String] = []
            words.reserveCapacity(count)
            for rank in 0..<count {
                let index = Int(
                    readU16(buf, header.freqRankOffset + rank * 2)
                )
                guard index < header.unigramCount else { continue }
                if let word = string(at: index, header: header, buf: buf) {
                    words.append(word)
                }
            }
            return words
        } ?? []
    }

    /// Prefix completions, highest frequency first.
    public func completions(prefix: String, limit: Int = 8) -> [String] {
        let needle = asciiLowered(prefix)
        guard !needle.isEmpty, limit > 0 else { return [] }
        return withMap { buf, header in
            var scored: [(Int, Int)] = []
            var index = lowerBound(needle, header: header, buf: buf)
            while index < header.unigramCount {
                guard let bytes = wordBytes(at: index, header: header, buf: buf) else { break }
                guard hasPrefix(bytes, needle) else { break }
                if !bytesEqual(bytes, needle) {
                    scored.append((index, frequency(at: index, header: header, buf: buf)))
                }
                index += 1
                // Soft cap scan to keep keystroke path cheap.
                if scored.count >= limit * 8 { break }
            }
            scored.sort { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0 < rhs.0
            }
            return scored.prefix(limit).compactMap { pair in
                string(at: pair.0, header: header, buf: buf)
            }
        } ?? []
    }

    /// Nearby words scored by QWERTY proximity + frequency. Does not decide
    /// whether autocorrect should fire — the suggestion engine does.
    public func scoredCorrections(for typed: String, limit: Int = 6) -> [EnglishScoredCorrection] {
        let needle = asciiLowered(typed)
        guard needle.count >= 3, let firstByte = needle.first, limit > 0 else { return [] }
        let first = Character(UnicodeScalar(firstByte))
        var initials = Set(EnglishQWERTYProximity.neighbors(of: first, includingSelf: true))
        initials.insert(first)

        return withMap { buf, header in
            var best: [ScoredIndex] = []
            best.reserveCapacity(limit)
            for initial in initials {
                guard let letter = initial.asciiLetterIndex else { continue }
                let rangeOffset = header.initialOffset + letter * 4
                let start = Int(readU16(buf, rangeOffset))
                let count = Int(readU16(buf, rangeOffset + 2))
                guard start >= 0, count >= 0, start + count <= header.unigramCount else { continue }
                for index in start..<(start + count) {
                    guard let bytes = wordBytes(at: index, header: header, buf: buf) else { continue }
                    let delta = abs(bytes.count - needle.count)
                    guard delta <= 2, !bytesEqual(bytes, needle) else { continue }
                    guard let alignment = EnglishQWERTYProximity.align(
                        typedASCII: needle,
                        candidateASCII: bytes
                    ) else { continue }
                    guard alignment.cost > 0 else { continue }
                    insertBest(
                        ScoredIndex(
                            index: index,
                            spatialCost: alignment.cost,
                            frequency: frequency(at: index, header: header, buf: buf),
                            isTransposition: alignment.isTransposition,
                            isShortening: alignment.isShortening
                        ),
                        into: &best,
                        limit: limit
                    )
                }
            }
            return best.compactMap { scored in
                guard let word = string(at: scored.index, header: header, buf: buf) else {
                    return nil
                }
                return EnglishScoredCorrection(
                    word: word,
                    spatialCost: scored.spatialCost,
                    frequency: scored.frequency,
                    isTransposition: scored.isTransposition,
                    isShortening: scored.isShortening
                )
            }
        } ?? []
    }

    /// Best proximity correction, or nil when the typed word is already known.
    public func bestCorrection(for typed: String) -> String? {
        if contains(typed) { return nil }
        return scoredCorrections(for: typed, limit: 1).first?.word
    }

    public func nextWords(after previous: String, limit: Int = 6) -> [String] {
        guard limit > 0 else { return [] }
        let needle = asciiLowered(previous)
        return withMap { buf, header in
            guard let prevIndex = lookupIndex(needle, header: header, buf: buf) else {
                return []
            }
            guard let group = lookupBigramGroup(prevIndex: prevIndex, header: header, buf: buf) else {
                return []
            }
            let count = min(limit, group.nextCount)
            var words: [String] = []
            words.reserveCapacity(count)
            for offset in 0..<count {
                let index = Int(readU16(buf, header.bigramNextOffset + (group.firstNext + offset) * 2))
                if let word = string(at: index, header: header, buf: buf) {
                    words.append(word)
                }
            }
            return words
        } ?? []
    }

    // MARK: - Mapped file

    private struct FileHeader {
        var unigramCount: Int
        var bigramGroupCount: Int
        var stringPoolOffset: Int
        var stringPoolSize: Int
        var unigramOffset: Int
        var freqRankOffset: Int
        var initialOffset: Int
        var bigramIndexOffset: Int
        var bigramNextOffset: Int
        var fileSize: Int

        static let magic = "OSGENG01"
        static let version = 1
        static let headerSize = 64
        static let initialCount = 26

        static func parse(_ data: Data) -> FileHeader? {
            guard data.count >= headerSize else { return nil }
            return data.withUnsafeBytes { buf -> FileHeader? in
                let magicBytes = UnsafeRawBufferPointer(rebasing: buf[0..<8])
                let magic = String(bytes: magicBytes, encoding: .ascii)
                guard magic == Self.magic else { return nil }
                guard Int(readU32(buf, 8)) == version else { return nil }
                let unigramCount = Int(readU32(buf, 12))
                let bigramGroupCount = Int(readU32(buf, 16))
                let stringPoolOffset = Int(readU32(buf, 20))
                let stringPoolSize = Int(readU32(buf, 24))
                let unigramOffset = Int(readU32(buf, 28))
                let freqRankOffset = Int(readU32(buf, 32))
                let initialOffset = Int(readU32(buf, 36))
                let bigramIndexOffset = Int(readU32(buf, 40))
                let bigramNextOffset = Int(readU32(buf, 44))
                let fileSize = data.count

                guard unigramCount >= 0, unigramCount <= 200_000 else { return nil }
                guard bigramGroupCount >= 0, bigramGroupCount <= 100_000 else { return nil }
                guard region(unigramOffset, unigramCount * 8, in: fileSize),
                      region(freqRankOffset, unigramCount * 2, in: fileSize),
                      region(initialOffset, initialCount * 4, in: fileSize),
                      region(bigramIndexOffset, bigramGroupCount * 8, in: fileSize),
                      region(stringPoolOffset, stringPoolSize, in: fileSize)
                else {
                    return nil
                }

                return FileHeader(
                    unigramCount: unigramCount,
                    bigramGroupCount: bigramGroupCount,
                    stringPoolOffset: stringPoolOffset,
                    stringPoolSize: stringPoolSize,
                    unigramOffset: unigramOffset,
                    freqRankOffset: freqRankOffset,
                    initialOffset: initialOffset,
                    bigramIndexOffset: bigramIndexOffset,
                    bigramNextOffset: bigramNextOffset,
                    fileSize: fileSize
                )
            }
        }

        private static func region(_ offset: Int, _ size: Int, in fileSize: Int) -> Bool {
            offset >= 0 && size >= 0 && offset <= fileSize && size <= fileSize - offset
        }
    }

    private struct ScoredIndex {
        var index: Int
        var spatialCost: Int
        var frequency: Int
        var isTransposition: Bool
        var isShortening: Bool
    }

    private struct BigramGroup {
        var nextCount: Int
        var firstNext: Int
    }

    private func loadMappedLexicon() {
        guard let url = Bundle(for: EnglishLexicon.self)
            .url(forResource: "english_lexicon", withExtension: "bin")
            ?? Bundle.main.url(forResource: "english_lexicon", withExtension: "bin")
        else {
            return
        }
        // `.mappedIfSafe` keeps the 40k table on file-backed pages. Jetsam
        // charges dirty heap, not these clean mapped pages.
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let parsed = FileHeader.parse(data)
        else {
            return
        }
        mapped = data
        header = parsed
        loaded = true
    }

    private func withMap<T>(_ body: (UnsafeRawBufferPointer, FileHeader) -> T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard loaded, let data = mapped, let header else { return nil }
        return data.withUnsafeBytes { buf in
            body(buf, header)
        }
    }

    private func lookupIndex(
        _ needle: [UInt8],
        header: FileHeader,
        buf: UnsafeRawBufferPointer
    ) -> Int? {
        let index = lowerBound(needle, header: header, buf: buf)
        guard index < header.unigramCount,
              let bytes = wordBytes(at: index, header: header, buf: buf),
              bytesEqual(bytes, needle)
        else {
            return nil
        }
        return index
    }

    private func lowerBound(
        _ needle: [UInt8],
        header: FileHeader,
        buf: UnsafeRawBufferPointer
    ) -> Int {
        var low = 0
        var high = header.unigramCount
        while low < high {
            let mid = (low + high) / 2
            guard let bytes = wordBytes(at: mid, header: header, buf: buf) else {
                high = mid
                continue
            }
            if compare(bytes, needle) < 0 {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func lookupBigramGroup(
        prevIndex: Int,
        header: FileHeader,
        buf: UnsafeRawBufferPointer
    ) -> BigramGroup? {
        var low = 0
        var high = header.bigramGroupCount
        while low < high {
            let mid = (low + high) / 2
            let midPrev = Int(readU16(buf, header.bigramIndexOffset + mid * 8))
            if midPrev < prevIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < header.bigramGroupCount else { return nil }
        let offset = header.bigramIndexOffset + low * 8
        guard Int(readU16(buf, offset)) == prevIndex else { return nil }
        return BigramGroup(
            nextCount: Int(readU16(buf, offset + 2)),
            firstNext: Int(readU32(buf, offset + 4))
        )
    }

    private func frequency(at index: Int, header: FileHeader, buf: UnsafeRawBufferPointer) -> Int {
        Int(readU16(buf, header.unigramOffset + index * 8 + 6))
    }

    private func wordBytes(
        at index: Int,
        header: FileHeader,
        buf: UnsafeRawBufferPointer
    ) -> UnsafeBufferPointer<UInt8>? {
        guard index >= 0, index < header.unigramCount else { return nil }
        let record = header.unigramOffset + index * 8
        let poolOff = Int(readU32(buf, record))
        let length = Int(buf[record + 4])
        let start = header.stringPoolOffset + poolOff
        guard length >= 0,
              start >= header.stringPoolOffset,
              start + length <= header.stringPoolOffset + header.stringPoolSize,
              start + length <= header.fileSize,
              let base = buf.baseAddress
        else {
            return nil
        }
        return UnsafeBufferPointer(
            start: base.advanced(by: start).assumingMemoryBound(to: UInt8.self),
            count: length
        )
    }

    private func string(
        at index: Int,
        header: FileHeader,
        buf: UnsafeRawBufferPointer
    ) -> String? {
        guard let bytes = wordBytes(at: index, header: header, buf: buf) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    private func insertBest(_ scored: ScoredIndex, into best: inout [ScoredIndex], limit: Int) {
        if let existing = best.firstIndex(where: { $0.index == scored.index }) {
            if isOrderedBefore(scored, best[existing]) {
                best[existing] = scored
                best.sort(by: isOrderedBefore)
            }
            return
        }
        if best.count < limit {
            best.append(scored)
            best.sort(by: isOrderedBefore)
            return
        }
        if let last = best.last, isOrderedBefore(scored, last) {
            best[best.count - 1] = scored
            best.sort(by: isOrderedBefore)
        }
    }

    private func isOrderedBefore(_ lhs: ScoredIndex, _ rhs: ScoredIndex) -> Bool {
        if lhs.spatialCost != rhs.spatialCost { return lhs.spatialCost < rhs.spatialCost }
        if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
        return lhs.index < rhs.index
    }
}

private func readU16(_ buf: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
    UInt16(littleEndian: buf.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
}

private func readU32(_ buf: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
    UInt32(littleEndian: buf.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
}

private func asciiLowered(_ string: String) -> [UInt8] {
    string.utf8.map { byte in
        (byte >= 65 && byte <= 90) ? byte + 32 : byte
    }
}

private func compare(_ word: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Int {
    let count = min(word.count, needle.count)
    for index in 0..<count {
        let left = word[index]
        let right = needle[index]
        if left < right { return -1 }
        if left > right { return 1 }
    }
    if word.count < needle.count { return -1 }
    if word.count > needle.count { return 1 }
    return 0
}

private func hasPrefix(_ word: UnsafeBufferPointer<UInt8>, _ prefix: [UInt8]) -> Bool {
    guard word.count >= prefix.count else { return false }
    for index in prefix.indices where word[index] != prefix[index] {
        return false
    }
    return true
}

private func bytesEqual(_ word: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
    guard word.count == needle.count else { return false }
    for index in needle.indices where word[index] != needle[index] {
        return false
    }
    return true
}

private extension Character {
    var asciiLetterIndex: Int? {
        guard let value = utf8.first, value >= 97, value <= 122 else { return nil }
        return Int(value - 97)
    }
}
