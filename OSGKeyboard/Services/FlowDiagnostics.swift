// FlowDiagnostics.swift
// OSGKeyboard · Main App
//
// Structured logging for the Flow dictation pipeline. Dual-writes to NSLog
// (`[OSGDiag/flow]`) and `OSGLog.flow` so Console shows lines even when the
// keyboard extension process is selected.

import Foundation
import OSGKeyboardShared

enum FlowDiagnostics {
    static func log(_ message: String) {
        OSGDiag.log(message, category: "flow")
    }

    static func logDrain(_ report: FlowCaptureDrainReport) {
        FlowPipelineDiagnostics.logDrain(report)
    }
}
