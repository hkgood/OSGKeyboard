// OSGLog.swift
// OSGKeyboard · Shared
//
// Unified os.Logger categories for cross-target diagnostics. Filter in
// Console.app with subsystem `com.osgkeyboard.ios`.

import os

public enum OSGLog {
    private static let subsystem = "com.osgkeyboard.ios"

    public static let flow = Logger(subsystem: subsystem, category: "flow")
    public static let clm = Logger(subsystem: subsystem, category: "clm")
    public static let config = Logger(subsystem: subsystem, category: "config")
    public static let asr = Logger(subsystem: subsystem, category: "asr")
    public static let keyboardExt = Logger(subsystem: subsystem, category: "keyboardExt")
}
