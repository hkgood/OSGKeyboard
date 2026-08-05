// HostMemoryBudget.swift
// OSGKeyboard · Shared
//
// Shared RSS gate for host-side heavy work (Rime deploy, CLM, ASR warmup).
// Keeps the keyboard extension alive by avoiding host jetsam spikes.

import Foundation

public enum HostMemoryBudget {
    /// Soft ceiling (MiB): defer CLM / Rime / ASR when resident memory is above this.
    /// Host SwiftUI baseline alone is often ~150–170 MB; 120 was always-trip and
    /// left Rime/CLM permanently deferred while wrongly signaling hostHeavy.
    public static let deferHeavyWorkAboveMB: Double = 260
    public static let projectedPeakCeilingMB: Double = 290

    public static var shouldDeferHeavyWork: Bool {
        let rss = OSGDiag.memoryMB()
        guard rss >= 0 else { return false }
        return rss >= deferHeavyWorkAboveMB
    }

    public static func gate(
        _ work: String,
        category: String = "flow"
    ) -> Bool {
        let rss = OSGDiag.memoryMB()
        let estimatedGrowth: Double
        if work.contains("clm") {
            estimatedGrowth = 48
        } else if work.contains("asr") {
            estimatedGrowth = 32
        } else if work.contains("rime") {
            estimatedGrowth = 24
        } else {
            estimatedGrowth = 24
        }
        if shouldDeferHeavyWork
            || (rss >= 0 && rss + estimatedGrowth >= projectedPeakCeilingMB) {
            OSGDiag.log(
                "memoryGate defer work=\(work) \(OSGDiag.memoryTag()) "
                    + "threshold=\(Int(deferHeavyWorkAboveMB))MB "
                    + "projected=\(Int(max(0, rss + estimatedGrowth)))MB",
                category: category
            )
            return false
        }
        return true
    }
}
