// MacAppContextService.swift
// OSGKeyboard · Mac
//
// Unlike the iOS keyboard extension, macOS can read the frontmost app's
// bundle ID via NSWorkspace and map it to `AppContext` for polish prompts.

import AppKit
import Foundation

enum MacAppContextService {
    /// Bundle IDs → coarse polish context (macOS + cross-platform).
    private static let contextByBundleId: [String: AppContext] = [
        // Code / dev
        "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code,
        "com.google.android.studio": .code,
        "com.jetbrains.intellij": .code,
        "com.jetbrains.AppCode": .code,
        "com.sublimetext.4": .code,
        "com.github.GitHubClient": .code,
        "com.apple.Terminal": .code,
        "com.googlecode.iterm2": .code,
        "dev.warp.Warp-Stable": .code,
        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.google.Gmail": .email,
        "com.readdle.smartemail": .email,
        // Chat / IM
        "com.tencent.xinWeChat": .chat,
        "com.tencent.qq": .chat,
        "com.tencent.wework": .chat,
        "com.tinyspeck.slackmacgap": .chat,
        "com.hnc.Discord": .chat,
        "com.microsoft.teams": .chat,
        "com.microsoft.teams2": .chat,
        "ru.keepcoder.Telegram": .chat,
        "net.whatsapp.WhatsApp": .chat,
        "com.apple.MobileSMS": .chat,
        "com.facebook.archon": .chat,
        "com.laiwang.DingTalk": .chat,
        "com.bytedance.feishu": .chat,
        // Documents / notes
        "com.apple.Notes": .document,
        "com.apple.iWork.Pages": .document,
        "notion.id": .document,
        "md.obsidian": .document,
        "net.shinyfrog.bear": .document,
        "com.agiletortoise.Drafts-OSX": .document,
        "com.microsoft.Word": .document,
        "com.google.GoogleDocs": .document,
        "com.evernote.Evernote": .document,
        "com.microsoft.onenote.mac": .document,
    ]

    /// Chat-style apps from the shared host registry (iOS bundle IDs often
    /// match Mac counterparts for cross-platform IM).
    private static let chatBundleIdsFromRegistry: Set<String> = {
        Set(HostAppURLRegistry.entries.map(\.bundleId))
    }()

    static func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    static func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    static func detectContext() -> AppContext {
        guard let bundleId = frontmostBundleIdentifier() else { return .unknown }
        if let mapped = contextByBundleId[bundleId] { return mapped }
        if chatBundleIdsFromRegistry.contains(bundleId) { return .chat }
        if bundleId.hasPrefix("com.apple.Safari") || bundleId.contains("chrome") {
            return .document
        }
        return .unknown
    }

    /// Persist detected context into the shared configuration store so
    /// `PolishingService` reads the same signal as on iOS.
    static func captureAndPersist(to store: AppGroupStore) {
        let context = detectContext()
        store.setDetectedAppContext(context)
    }
}
