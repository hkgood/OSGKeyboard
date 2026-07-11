// ProviderToolRunnerState.swift
// OSGKeyboard · Shared
//
// Pure state machine for Settings provider tool rows (validate / fetch models).

import Foundation

public struct ProviderToolRunnerState: Equatable, Sendable {
    public var isRunning: Bool
    public var message: String?
    public var failed: Bool
    public var models: [String]

    public init(
        isRunning: Bool = false,
        message: String? = nil,
        failed: Bool = false,
        models: [String] = []
    ) {
        self.isRunning = isRunning
        self.message = message
        self.failed = failed
        self.models = models
    }
}

@MainActor
public enum ProviderToolRunner {
    public static func runValidate(
        runningMessage: String,
        successMessage: String,
        validate: () async throws -> Void
    ) async -> ProviderToolRunnerState {
        var state = ProviderToolRunnerState(isRunning: true, message: runningMessage, failed: false)
        do {
            try await validate()
            state.isRunning = false
            state.message = successMessage
            state.failed = false
        } catch {
            state.isRunning = false
            state.failed = true
            state.message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        return state
    }

    public static func runFetchModels(
        runningMessage: String,
        loadedMessage: (Int) -> String,
        emptyMessage: String,
        currentModel: String,
        fetchModels: () async throws -> [String]
    ) async -> (state: ProviderToolRunnerState, selectedModel: String?) {
        var state = ProviderToolRunnerState(isRunning: true, message: runningMessage, failed: false)
        do {
            let fetched = try await fetchModels()
            guard !fetched.isEmpty else {
                state.isRunning = false
                state.failed = true
                state.message = emptyMessage
                state.models = []
                return (state, nil)
            }

            var resolved = fetched
            let trimmed = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !resolved.contains(trimmed) {
                resolved.insert(trimmed, at: 0)
            }
            state.models = resolved
            state.isRunning = false
            state.failed = false
            state.message = loadedMessage(resolved.count)

            let selected: String?
            if trimmed.isEmpty, let first = resolved.first {
                selected = first
            } else {
                selected = nil
            }
            return (state, selected)
        } catch {
            state.isRunning = false
            state.failed = true
            state.message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            state.models = []
            return (state, nil)
        }
    }
}

public enum HardTimeout {
    /// Returns the first completed result; the losing task is cancelled.
    public static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    /// Non-throwing variant for tasks that should fall back when time elapses.
    public static func value<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T,
        onTimeout: @escaping @Sendable () -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return onTimeout()
            }
            let result = await group.next() ?? onTimeout()
            group.cancelAll()
            return result
        }
    }
}
