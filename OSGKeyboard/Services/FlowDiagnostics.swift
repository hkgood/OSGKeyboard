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
        FlowFailureLogStore.shared.record(message)
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
        let url = FlowFailureLogStore.shared.persistStartupFailure(
            reason: reason,
            context: context
        )
        if let url {
            OSGDiag.log(
                "Flow startup failure report saved file=\(url.lastPathComponent)",
                category: "flow"
            )
        } else {
            OSGDiag.log("Flow startup failure report could not be saved", category: "flow")
        }
        return url
    }
}
