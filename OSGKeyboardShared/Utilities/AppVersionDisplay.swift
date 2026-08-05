// AppVersionDisplay.swift
// OSGKeyboardShared
//
// Reads marketing / build numbers from the host app Info.plist for Settings.

import Foundation

/// Display helpers for the app's marketing version and build number.
public enum AppVersionDisplay {
    /// `CFBundleShortVersionString`, e.g. `"1.5.0"`.
    public static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// `CFBundleVersion`, e.g. `"37"`.
    public static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// Settings trailing label, e.g. `"1.5.0 (Build 37)"`.
    public static var detailedLabel: String {
        "\(marketingVersion) (Build \(buildNumber))"
    }
}
