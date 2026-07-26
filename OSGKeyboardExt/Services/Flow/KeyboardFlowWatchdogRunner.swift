// KeyboardFlowWatchdogRunner.swift
// OSGKeyboard · Keyboard Extension
//
// Watchdog task lifecycle extracted from KeyboardFlowCoordinator.

import Foundation
import OSGKeyboardShared

@MainActor
final class KeyboardFlowWatchdogRunner {
    private(set) var task: Task<Void, Never>?

    func stop() {
        task?.cancel()
        task = nil
    }

    func start(_ body: @escaping @MainActor () async -> Void) {
        stop()
        task = Task { @MainActor in
            await body()
        }
    }
}
