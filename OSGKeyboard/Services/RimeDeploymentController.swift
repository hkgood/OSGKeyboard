// RimeDeploymentController.swift
// OSGKeyboard · Main App
//
// Single entry point for user-visible Rime deployment.
//
// Chinese typing is unusable until Rime is deployed, so this controller runs
// host-owned deployment immediately when resources are missing and exposes an
// observable outcome to onboarding and Settings. The keyboard extension only
// reads readiness and opens the already-built data.

import Combine
import Foundation
import OSGKeyboardShared

@MainActor
final class RimeDeploymentController: ObservableObject {
    static let shared = RimeDeploymentController()

    enum Status: Equatable {
        case idle
        case deploying
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private var activeTask: Task<Void, Never>?

    var isDeploying: Bool { status == .deploying }

    init() {
        status = RimeResourceInstaller.isReady ? .ready : .idle
    }

    /// Re-reads App Group state, e.g. after another process deployed.
    func refreshStatus() {
        guard !isDeploying else { return }
        if RimeResourceInstaller.isReady {
            status = .ready
        } else if case .failed = status {
            // Keep the failure visible until a retry actually runs.
        } else {
            status = .idle
        }
    }

    /// Deploys right away, deliberately skipping the warmup delay, foreground
    /// check, and memory gate. Callers are moments where the user is waiting on
    /// the result and cannot be racing the keyboard extension for memory.
    func deployNow(force: Bool = false, reason: String) {
        guard activeTask == nil else { return }
        if !force, RimeResourceInstaller.isReady {
            status = .ready
            return
        }

        OSGDiag.log("rime.deployNow begin reason=\(reason) \(OSGDiag.memoryTag())", category: "flow")
        status = .deploying
        let snapshot = TypingInputConfiguration.shared.snapshot

        activeTask = Task { @MainActor in
            defer { activeTask = nil }
            // Mirrors the warmup path so the keyboard defers its own prepare
            // while librime maintenance is running.
            FlowSessionBridge.setHostHeavy(true)

            do {
                try await RimeResourceInstaller.shared.installIfNeeded(
                    configuration: snapshot,
                    force: force
                )
                // Release the heavy-work gate before notifying the extension.
                // Its observer retries immediately and must not see stale busy
                // state, or the error remains until the keyboard is reopened.
                FlowSessionBridge.setHostHeavy(false)
                AppGroupConfigDarwin.postConfigChanged()
                status = .ready
                OSGDiag.log(
                    "rime.deployNow done reason=\(reason) \(OSGDiag.memoryTag())",
                    category: "flow"
                )
            } catch {
                FlowSessionBridge.setHostHeavy(false)
                status = .failed(error.localizedDescription)
                OSGDiag.log(
                    "rime.deployNow failed reason=\(reason) error=\(error.localizedDescription)",
                    category: "flow"
                )
            }
        }
    }

    /// Wipes implicit typing habits under the same hostHeavy gate as deploy,
    /// so the keyboard extension cannot keep LevelDB open while files vanish.
    func clearTypingHabits() {
        guard activeTask == nil else { return }

        OSGDiag.log("typing.habits.clear begin \(OSGDiag.memoryTag())", category: "flow")
        status = .deploying
        activeTask = Task { @MainActor in
            defer { activeTask = nil }
            FlowSessionBridge.setHostHeavy(true)
            do {
                try await TypingHabitStore.clearAll()
                FlowSessionBridge.setHostHeavy(false)
                AppGroupConfigDarwin.postConfigChanged()
                status = RimeResourceInstaller.isReady ? .ready : .idle
                OSGDiag.log("typing.habits.clear done \(OSGDiag.memoryTag())", category: "flow")
            } catch {
                FlowSessionBridge.setHostHeavy(false)
                status = .failed(error.localizedDescription)
                OSGDiag.log(
                    "typing.habits.clear failed error=\(error.localizedDescription)",
                    category: "flow"
                )
            }
        }
    }
}
