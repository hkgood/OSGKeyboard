// MicrophonePriority.swift
// OSGKeyboard · Shared
//
// Device-local microphone ordering shared by the iOS and macOS capture paths.
// Hardware UIDs are not portable, so this setting deliberately does not join
// the iCloud settings payload.

import Foundation

public enum MicrophoneDeviceKind: String, Codable, Sendable, CaseIterable {
    case builtIn
    case bluetooth
    case usb
    case wired
    case virtual
    case other
}

public struct MicrophonePriorityDevice: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: MicrophoneDeviceKind

    public init(id: String, name: String, kind: MicrophoneDeviceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct MicrophonePriorityConfiguration: Codable, Equatable, Sendable {
    public var prioritized: [MicrophonePriorityDevice]
    public var excluded: [MicrophonePriorityDevice]

    public init(
        prioritized: [MicrophonePriorityDevice] = [],
        excluded: [MicrophonePriorityDevice] = []
    ) {
        self.prioritized = prioritized
        self.excluded = excluded
        sanitize()
    }

    public static let empty = MicrophonePriorityConfiguration()

    /// Refresh known metadata and append newly-seen devices at the lowest
    /// priority. Excluded UIDs remain excluded across disconnect/reconnect.
    public func merging(
        available: [MicrophonePriorityDevice]
    ) -> MicrophonePriorityConfiguration {
        var copy = self
        copy.merge(available: available)
        return copy
    }

    public mutating func merge(available: [MicrophonePriorityDevice]) {
        let availableByID = Dictionary(
            available.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        prioritized = prioritized.map { availableByID[$0.id] ?? $0 }
        excluded = excluded.map { availableByID[$0.id] ?? $0 }

        var known = Set(prioritized.map(\.id))
        known.formUnion(excluded.map(\.id))
        for device in available where known.insert(device.id).inserted {
            prioritized.append(device)
        }
        sanitize()
    }

    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        let validOffsets = fromOffsets.filter { prioritized.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }
        let moved = validOffsets.map { prioritized[$0] }
        for index in validOffsets.reversed() {
            prioritized.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let insertionIndex = min(
            max(0, toOffset - removedBeforeDestination),
            prioritized.count
        )
        prioritized.insert(contentsOf: moved, at: insertionIndex)
    }

    public mutating func exclude(atOffsets offsets: IndexSet) {
        let removed = offsets.sorted().compactMap { index in
            prioritized.indices.contains(index) ? prioritized[index] : nil
        }
        for index in offsets.sorted(by: >) where prioritized.indices.contains(index) {
            prioritized.remove(at: index)
        }
        let excludedIDs = Set(excluded.map(\.id))
        excluded.append(contentsOf: removed.filter { !excludedIDs.contains($0.id) })
        sanitize()
    }

    public mutating func exclude(id: String) {
        guard let index = prioritized.firstIndex(where: { $0.id == id }) else { return }
        exclude(atOffsets: IndexSet(integer: index))
    }

    public mutating func restore(id: String) {
        guard let index = excluded.firstIndex(where: { $0.id == id }) else { return }
        let device = excluded.remove(at: index)
        if !prioritized.contains(where: { $0.id == id }) {
            prioritized.append(device)
        }
        sanitize()
    }

    public func preferredDevice(
        available: [MicrophonePriorityDevice]
    ) -> MicrophonePriorityDevice? {
        let availableByID = Dictionary(
            available.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for preference in prioritized {
            if let device = availableByID[preference.id] {
                return device
            }
        }
        return nil
    }

    private mutating func sanitize() {
        prioritized = Self.uniqueDevices(prioritized)
        let prioritizedIDs = Set(prioritized.map(\.id))
        excluded = Self.uniqueDevices(excluded).filter { !prioritizedIDs.contains($0.id) }
    }

    private static func uniqueDevices(
        _ devices: [MicrophonePriorityDevice]
    ) -> [MicrophonePriorityDevice] {
        var seen = Set<String>()
        return devices.compactMap { device in
            let trimmedID = device.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, seen.insert(trimmedID).inserted else { return nil }
            let trimmedName = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return MicrophonePriorityDevice(
                id: trimmedID,
                name: trimmedName.isEmpty ? trimmedID : trimmedName,
                kind: device.kind
            )
        }
    }
}
