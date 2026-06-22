// FlowDiagnostics.swift
// OSGKeyboard · Main App
//
// Structured logging for the Flow dictation pipeline. Visible in Xcode
// console (DEBUG) and Console.app via `subsystem: com.osgkeyboard.ios`.

import Foundation
import os

enum FlowDiagnostics {
    private static let logger = Logger(
        subsystem: "com.osgkeyboard.ios",
        category: "Flow"
    )

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("🌊[OSGFlow] \(message)")
        #endif
    }
}
