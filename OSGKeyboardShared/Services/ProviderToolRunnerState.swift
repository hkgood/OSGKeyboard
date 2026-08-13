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

public enum ProviderToolCompletion: Equatable, Sendable {
    case completed(ProviderToolRunnerState)
    case cancelled
}

public enum ProviderModelFetchCompletion: Equatable, Sendable {
    case completed(state: ProviderToolRunnerState, selectedModel: String?)
    case cancelled
}

/// Immutable operation captured synchronously by a Settings tool button.
/// The coordinator only retains the resulting task handle, generation, and
/// provider identity; it never stores request credentials or configuration.
public struct ProviderToolRequest<Output: Sendable>: Sendable {
    public let providerIdentity: String
    public let operation: @Sendable () async throws -> Output

    public init(
        providerIdentity: String,
        operation: @escaping @Sendable () async throws -> Output
    ) {
        self.providerIdentity = providerIdentity
        self.operation = operation
    }
}

public enum ProviderToolCancellation {
    public static func matches(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let llmError = error as? LLMError, llmError == .cancelled {
            return true
        }
        return false
    }
}

/// Main-actor request gate shared by iOS and macOS Settings rows.
///
/// Task cancellation is best-effort. The monotonically increasing generation
/// and provider identity are the correctness boundary for late completions.
@MainActor
public final class ProviderToolRequestCoordinator {
    public private(set) var task: Task<Void, Never>?
    public private(set) var generation: UInt64 = 0

    private var providerIdentity: String?

    public init() {}

    public var isRunning: Bool {
        task != nil
    }

    public func start<Output: Sendable>(
        providerIdentity: String,
        operation: @escaping @Sendable () async -> Output,
        commit: @escaping @MainActor (Output) -> Void
    ) {
        task?.cancel()
        generation &+= 1
        let requestGeneration = generation
        self.providerIdentity = providerIdentity

        task = Task { [weak self] in
            let output = await operation()
            guard let self,
                  self.generation == requestGeneration,
                  self.providerIdentity == providerIdentity else {
                return
            }
            self.task = nil
            commit(output)
        }
    }

    public func invalidate() {
        generation &+= 1
        providerIdentity = nil
        task?.cancel()
        task = nil
    }
}

public enum ProviderToolRunner {
    public static func runValidate(
        runningMessage: String,
        successMessage: String,
        validate: @Sendable () async throws -> Void
    ) async -> ProviderToolCompletion {
        var state = ProviderToolRunnerState(isRunning: true, message: runningMessage, failed: false)
        do {
            try await validate()
            state.isRunning = false
            state.message = successMessage
            state.failed = false
        } catch where ProviderToolCancellation.matches(error) {
            return .cancelled
        } catch {
            state.isRunning = false
            state.failed = true
            state.message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        return .completed(state)
    }

    public static func runFetchModels(
        runningMessage: String,
        loadedMessage: @Sendable (Int) -> String,
        emptyMessage: String,
        currentModel: String,
        fetchModels: @Sendable () async throws -> [String]
    ) async -> ProviderModelFetchCompletion {
        var state = ProviderToolRunnerState(isRunning: true, message: runningMessage, failed: false)
        do {
            let fetched = try await fetchModels()
            guard !fetched.isEmpty else {
                state.isRunning = false
                state.failed = true
                state.message = emptyMessage
                state.models = []
                return .completed(state: state, selectedModel: nil)
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
            return .completed(state: state, selectedModel: selected)
        } catch where ProviderToolCancellation.matches(error) {
            return .cancelled
        } catch {
            state.isRunning = false
            state.failed = true
            state.message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            state.models = []
            return .completed(state: state, selectedModel: nil)
        }
    }
}

private final class HardTimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var resolved = false
    private var pendingResult: Result<T, Error>?

    func install(
        continuation: CheckedContinuation<T, Error>,
        tasks: [Task<Void, Never>]
    ) {
        lock.lock()
        if resolved {
            let result = pendingResult
            pendingResult = nil
            lock.unlock()
            tasks.forEach { $0.cancel() }
            if let result {
                continuation.resume(with: result)
            }
            return
        }
        self.continuation = continuation
        self.tasks = tasks
        lock.unlock()
    }

    func resolve(_ result: Result<T, Error>) {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return
        }
        resolved = true
        let continuation = self.continuation
        let tasks = self.tasks
        if continuation == nil {
            pendingResult = result
        }
        self.continuation = nil
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}

public enum HardTimeout {
    /// Returns at the deadline even when the losing operation ignores
    /// cooperative cancellation. The detached loser is still cancelled, but
    /// is no longer a structured child that can hold the caller open.
    public static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = HardTimeoutRace<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operationTask = Task {
                    do {
                        race.resolve(.success(try await operation()))
                    } catch {
                        race.resolve(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)
                        )
                        race.resolve(.failure(CancellationError()))
                    } catch {
                        // The operation won and cancelled this timer.
                    }
                }
                race.install(
                    continuation: continuation,
                    tasks: [operationTask, timeoutTask]
                )
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }

    /// Non-throwing variant for tasks that should fall back when time elapses.
    public static func value<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T,
        onTimeout: @escaping @Sendable () -> T
    ) async -> T {
        do {
            return try await run(seconds: seconds) {
                await operation()
            }
        } catch {
            return onTimeout()
        }
    }
}
