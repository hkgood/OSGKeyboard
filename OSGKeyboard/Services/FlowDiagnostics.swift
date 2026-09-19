// FlowDiagnostics.swift
// OSGKeyboard · Main App
//
// Structured logging for the Flow dictation pipeline. Dual-writes to NSLog
// (`[OSGDiag/flow]`) and `OSGLog.flow` so Console shows lines even when the
// keyboard extension process is selected, and feeds the shared breadcrumb
// window that startup-failure reports are cut from.

import Foundation
import OSGKeyboardShared

enum FlowDiagnostics {
    static func log(_ message: String) {
        FlowFailureDiagnostics.record(message)
        OSGDiag.log(message, category: "flow")
    }

    static func logDrain(_ report: FlowCaptureDrainReport) {
        FlowPipelineDiagnostics.logDrain(report)
    }

    @discardableResult
    static func persistStartupFailure(
        reason: String,
        context: [String: String]
    ) -> URL? {
        FlowFailureDiagnostics.persistStartupFailure(reason: reason, context: context)
    }
}
