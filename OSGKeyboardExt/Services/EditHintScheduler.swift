// EditHintScheduler.swift
// OSGKeyboard · Keyboard Extension
//
// Owns the edit-hint lifetime so every producer shares one expiration order.

import Foundation
import OSGKeyboardShared

@MainActor
final class EditHintScheduler {
    typealias Sleeper = @MainActor (Duration) async -> Void

    private let state: KeyboardState
    private let sleeper: Sleeper
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        state: KeyboardState,
        sleeper: @escaping Sleeper = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.state = state
        self.sleeper = sleeper
    }

    func show(message: String, isPositive: Bool, duration: Duration) {
        let scheduledGeneration = advanceGeneration()
        task?.cancel()

        state.editHint = message
        state.editHintIsPositive = isPositive

        let sleeper = sleeper
        task = Task { @MainActor [weak self, sleeper] in
            await sleeper(duration)
            guard let self, self.generation == scheduledGeneration else {
                return
            }
            self.task = nil
            self.clearHint()
        }
    }

    func clearPositive() {
        guard state.editHintIsPositive else { return }
        advanceGeneration()
        task?.cancel()
        task = nil
        clearHint()
    }

    func invalidate() {
        advanceGeneration()
        task?.cancel()
        task = nil
        clearHint()
    }

    @discardableResult
    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func clearHint() {
        state.editHint = nil
        state.editHintIsPositive = false
    }
}
