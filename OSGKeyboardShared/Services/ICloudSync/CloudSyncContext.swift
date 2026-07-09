// CloudSyncContext.swift
// OSGKeyboard · Shared
//
// Injectable AppCloudSync instance so iOS and Mac share one sync graph.

import Foundation

@MainActor
public enum CloudSyncContext {
    private static var configured: AppCloudSync?

    public static var shared: AppCloudSync {
        configured ?? AppCloudSync.shared
    }

    public static func configure(_ sync: AppCloudSync) {
        configured = sync
    }
}
