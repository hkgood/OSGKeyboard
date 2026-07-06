// FlowDiagnostics.swift
// OSGKeyboard · Main App
//
// Structured logging for the Flow dictation pipeline. Delegates to
// `OSGLog.flow` for Console.app visibility.

import Foundation
import OSGKeyboardShared

enum FlowDiagnostics {
    static func log(_ message: String) {
        OSGLog.flow.info("\(message, privacy: .public)")
    }

    static func logDrain(_ report: FlowCaptureDrainReport) {
        FlowPipelineDiagnostics.logDrain(report)
    }
}
