// MicrophonePriorityStore.swift
// OSGKeyboard · Shared

import Foundation

public struct MicrophonePriorityStore: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroupStore().defaults
    }

    public var hasStoredConfiguration: Bool {
        defaults.data(forKey: AppGroupConfiguration.Keys.microphonePriority) != nil
    }

    public func load() -> MicrophonePriorityConfiguration {
        guard let data = defaults.data(forKey: AppGroupConfiguration.Keys.microphonePriority) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(MicrophonePriorityConfiguration.self, from: data)
        } catch {
            OSGLog.config.warning(
                "microphone priority decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return .empty
        }
    }

    public func save(_ configuration: MicrophonePriorityConfiguration) {
        do {
            defaults.set(
                try JSONEncoder().encode(configuration),
                forKey: AppGroupConfiguration.Keys.microphonePriority
            )
        } catch {
            OSGLog.config.warning(
                "microphone priority encode failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @discardableResult
    public func mergeAndSave(
        available: [MicrophonePriorityDevice]
    ) -> MicrophonePriorityConfiguration {
        let merged = load().merging(available: available)
        save(merged)
        return merged
    }
}
