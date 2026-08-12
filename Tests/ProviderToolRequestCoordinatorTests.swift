// ProviderToolRequestCoordinatorTests.swift
// OSGKeyboard · Shared iOS/macOS tests

import Foundation
import XCTest
#if os(macOS)
@testable import OSGKeyboard
#else
@testable import OSGKeyboardShared
#endif

private actor SuspendedValue<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var pendingValue: Value?

    func value() async -> Value {
        if let pendingValue {
            self.pendingValue = nil
            return pendingValue
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning value: Value) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            pendingValue = value
        }
    }
}

@MainActor
final class ProviderToolRequestCoordinatorTests: XCTestCase {
    func testSlowACompletingAfterFastBDoesNotOverwriteB() async {
        let slowA = SuspendedValue<String>()
        let fastB = SuspendedValue<String>()
        let coordinator = ProviderToolRequestCoordinator()
        var committed: [String] = []

        coordinator.start(providerIdentity: "provider") {
            await slowA.value()
        } commit: {
            committed.append($0)
        }
        coordinator.start(providerIdentity: "provider") {
            await fastB.value()
        } commit: {
            committed.append($0)
        }

        await fastB.resume(returning: "B")
        await waitUntil { committed == ["B"] }
        await slowA.resume(returning: "A")
        await drainTasks()

        XCTAssertEqual(committed, ["B"])
        XCTAssertEqual(coordinator.generation, 2)
    }

    func testInvalidatedTaskThatIgnoresCancellationCannotCommit() async {
        let ignoredCancellation = SuspendedValue<String>()
        let coordinator = ProviderToolRequestCoordinator()
        var committed: String?

        coordinator.start(providerIdentity: "provider-a") {
            await ignoredCancellation.value()
        } commit: {
            committed = $0
        }
        coordinator.invalidate()

        await ignoredCancellation.resume(returning: "stale")
        await drainTasks()

        XCTAssertNil(committed)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.generation, 2)
    }

    func testCancellationErrorsReturnCancelledInsteadOfFailure() async {
        let cancellation = await ProviderToolRunner.runValidate(
            runningMessage: "running",
            successMessage: "success"
        ) {
            throw CancellationError()
        }
        let urlCancellation = await ProviderToolRunner.runValidate(
            runningMessage: "running",
            successMessage: "success"
        ) {
            throw URLError(.cancelled)
        }
        let llmCancellation = await ProviderToolRunner.runValidate(
            runningMessage: "running",
            successMessage: "success"
        ) {
            throw LLMError.cancelled
        }

        XCTAssertEqual(cancellation, .cancelled)
        XCTAssertEqual(urlCancellation, .cancelled)
        XCTAssertEqual(llmCancellation, .cancelled)
    }

    func testProviderIdentitySwitchRejectsOldCompletion() async {
        let providerA = SuspendedValue<String>()
        let providerB = SuspendedValue<String>()
        let coordinator = ProviderToolRequestCoordinator()
        var committed: String?

        coordinator.start(providerIdentity: "provider-a") {
            await providerA.value()
        } commit: {
            committed = $0
        }
        coordinator.start(providerIdentity: "provider-b") {
            await providerB.value()
        } commit: {
            committed = $0
        }

        await providerA.resume(returning: "A")
        await drainTasks()
        XCTAssertNil(committed)

        await providerB.resume(returning: "B")
        await waitUntil { committed == "B" }
        XCTAssertEqual(committed, "B")
    }

    func testFetchCompletionCannotOverwriteNewerModel() async {
        let fetchedModels = SuspendedValue<[String]>()
        let coordinator = ProviderToolRequestCoordinator()
        var model = ""
        var models = ["existing"]
        let requestModel = model

        coordinator.start(providerIdentity: "provider") {
            await ProviderToolRunner.runFetchModels(
                runningMessage: "running",
                loadedMessage: { "loaded \($0)" },
                emptyMessage: "empty",
                currentModel: requestModel
            ) {
                await fetchedModels.value()
            }
        } commit: { outcome in
            guard case .completed(let state, let selectedModel) = outcome else { return }
            models = state.models
            if let selectedModel {
                model = selectedModel
            }
        }

        model = "new-user-model"
        coordinator.invalidate()
        await fetchedModels.resume(returning: ["old-fetched-model"])
        await drainTasks()

        XCTAssertEqual(model, "new-user-model")
        XCTAssertEqual(models, ["existing"])
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous commit", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}
