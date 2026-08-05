// PersonalDictionaryRimeSync.swift
// OSGKeyboard · Shared
//
// Debounces PersonalDictionary mutations on the iOS host and redeploys
// Rime so the osg_personal sidecar matches. The keyboard extension only
// picks this up the next time it opens a typing session.

import Foundation

@MainActor
public enum PersonalDictionaryRimeSync {
    private static var pending: Task<Void, Never>?
    private static let debounceNanoseconds: UInt64 = 750_000_000
    private static let retryNanoseconds: UInt64 = 5_000_000_000

    /// Call after App Group personal-dictionary writes (add / delete / sync).
    /// Safe from any executor — work is hoppped onto the main actor.
    public nonisolated static func scheduleAfterDictionaryChange() {
        Task { @MainActor in
            scheduleOnMainActor()
        }
    }

    public static func deployNow() async {
        pending?.cancel()
        pending = nil
        await deploy(retryOnMemoryPressure: false)
    }

    private static func scheduleOnMainActor() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await deploy(retryOnMemoryPressure: true)
        }
    }

    private static func deploy(retryOnMemoryPressure: Bool) async {
        guard HostMemoryBudget.gate("rime.personalDictionary") else {
            OSGDiag.log("rime.personalDictionary deferred by memory gate", category: "boot")
            if retryOnMemoryPressure {
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(nanoseconds: retryNanoseconds)
                    guard !Task.isCancelled else { return }
                    await deploy(retryOnMemoryPressure: true)
                }
            }
            return
        }

        FlowSessionBridge.setHostHeavy(true)
        defer { FlowSessionBridge.setHostHeavy(false) }

        let typingConfig = TypingInputConfiguration.shared.snapshot
        let dictionary = AppGroupStore().personalDictionary
        do {
            try await RimeResourceInstaller.shared.installIfNeeded(
                configuration: typingConfig,
                personalDictionary: dictionary,
                force: false
            )
            OSGDiag.log("rime.personalDictionary deploy done", category: "boot")
        } catch {
            OSGDiag.log(
                "rime.personalDictionary deploy failed error=\(error.localizedDescription)",
                category: "boot"
            )
        }
    }
}
