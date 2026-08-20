// OSGDiag.swift
// OSGKeyboard · Shared
//
// Always-on diagnostic breadcrumbs. Uses NSLog so lines show up in Xcode /
// Console without needing an os.Logger subsystem filter (keyboard extension
// OSLog lines are easy to miss when the host process is selected).

import Darwin
import Foundation

public enum OSGDiag {
    public struct MemorySnapshot: Sendable, Equatable {
        public let rssMB: Double
        public let physFootprintMB: Double

        public init(rssMB: Double, physFootprintMB: Double) {
            self.rssMB = rssMB
            self.physFootprintMB = physFootprintMB
        }
    }

    /// Prefix every line for easy Console search: `OSGDiag`
    public static func log(_ message: String, category: String = "diag") {
        let line = "[OSGDiag/\(category)] \(message)"
        NSLog("%@", line)
        switch category {
        case "keyboardExt", "boot", "memory":
            OSGLog.keyboardExt.info("\(line, privacy: .public)")
        case "flow", "asr":
            OSGLog.flow.info("\(line, privacy: .public)")
        case "skills":
            OSGLog.config.info("\(line, privacy: .public)")
        default:
            OSGLog.config.info("\(line, privacy: .public)")
        }
    }

    /// Resident set size in MiB, or -1 if unavailable.
    public static func memoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / 1_048_576.0
    }

    /// Physical footprint in MiB. iOS jetsam tracks this more closely than RSS.
    public static func physFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    public static func memorySnapshot() -> MemorySnapshot {
        MemorySnapshot(rssMB: memoryMB(), physFootprintMB: physFootprintMB())
    }

    public static func memoryTag() -> String {
        let snapshot = memorySnapshot()
        return String(
            format: "rss=%.1fMB foot=%.1fMB",
            snapshot.rssMB,
            snapshot.physFootprintMB
        )
    }
}
