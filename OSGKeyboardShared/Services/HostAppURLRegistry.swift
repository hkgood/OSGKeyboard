// HostAppURLRegistry.swift
// OSGKeyboard · Shared
//
// Public URL-scheme whitelist for returning to a known host app after a
// cold-start Flow session handoff. One bundle id maps to one preferred URL.

import Foundation

public struct HostAppEntry: Sendable, Equatable {
    public let bundleId: String
    public let displayNameKey: String
    public let returnURLString: String
    public let tier: Int

    public var returnURL: URL? {
        URL(string: returnURLString)
    }

    public init(bundleId: String, displayNameKey: String, returnURLString: String, tier: Int) {
        self.bundleId = bundleId
        self.displayNameKey = displayNameKey
        self.returnURLString = returnURLString
        self.tier = tier
    }
}

public enum HostAppURLRegistry {
    /// Curated whitelist for high-frequency host apps (IM, work, notes).
    public static let entries: [HostAppEntry] = [
        // Tier 1 — China IM / work
        HostAppEntry(
            bundleId: "com.tencent.xin",
            displayNameKey: "hostApp.wechat",
            returnURLString: "weixin://",
            tier: 1
        ),
        HostAppEntry(
            bundleId: "com.tencent.mqq",
            displayNameKey: "hostApp.qq",
            returnURLString: "mqq://",
            tier: 1
        ),
        HostAppEntry(
            bundleId: "com.tencent.wework",
            displayNameKey: "hostApp.wecom",
            returnURLString: "wxwork://",
            tier: 1
        ),
        HostAppEntry(
            bundleId: "com.laiwang.DingTalk",
            displayNameKey: "hostApp.dingtalk",
            returnURLString: "dingtalk://",
            tier: 1
        ),
        HostAppEntry(
            bundleId: "com.bytedance.ee.lark",
            displayNameKey: "hostApp.lark",
            returnURLString: "lark://",
            tier: 1
        ),
        // Tier 2 — global IM / collaboration
        HostAppEntry(
            bundleId: "ph.telegra.Telegraph",
            displayNameKey: "hostApp.telegram",
            returnURLString: "tg://",
            tier: 2
        ),
        HostAppEntry(
            bundleId: "net.whatsapp.WhatsApp",
            displayNameKey: "hostApp.whatsapp",
            returnURLString: "whatsapp://",
            tier: 2
        ),
        HostAppEntry(
            bundleId: "jp.naver.line",
            displayNameKey: "hostApp.line",
            returnURLString: "line://",
            tier: 2
        ),
        HostAppEntry(
            bundleId: "com.facebook.Messenger",
            displayNameKey: "hostApp.messenger",
            returnURLString: "fb-messenger://",
            tier: 2
        ),
        HostAppEntry(
            bundleId: "com.tinyspeck.chatlyio",
            displayNameKey: "hostApp.slack",
            returnURLString: "slack://",
            tier: 2
        ),
        HostAppEntry(
            bundleId: "com.microsoft.skype.teams",
            displayNameKey: "hostApp.teams",
            returnURLString: "msteams://",
            tier: 2
        ),
        HostAppEntry(
            bundleId: "com.hammerandchisel.discord",
            displayNameKey: "hostApp.discord",
            returnURLString: "discord://",
            tier: 2
        ),
        // Tier 3 — notes / mail / browser
        HostAppEntry(
            bundleId: "notion.id",
            displayNameKey: "hostApp.notion",
            returnURLString: "notion://",
            tier: 3
        ),
        HostAppEntry(
            bundleId: "net.shinyfrog.bear",
            displayNameKey: "hostApp.bear",
            returnURLString: "bear://",
            tier: 3
        ),
        HostAppEntry(
            bundleId: "md.obsidian",
            displayNameKey: "hostApp.obsidian",
            returnURLString: "obsidian://",
            tier: 3
        ),
        HostAppEntry(
            bundleId: "com.agiletortoise.Drafts5",
            displayNameKey: "hostApp.drafts",
            returnURLString: "drafts5://",
            tier: 3
        ),
        HostAppEntry(
            bundleId: "com.google.Gmail",
            displayNameKey: "hostApp.gmail",
            returnURLString: "googlegmail://",
            tier: 3
        ),
        HostAppEntry(
            bundleId: "com.microsoft.Office.Outlook",
            displayNameKey: "hostApp.outlook",
            returnURLString: "ms-outlook://",
            tier: 3
        ),
        HostAppEntry(
            bundleId: "com.google.chrome.ios",
            displayNameKey: "hostApp.chrome",
            returnURLString: "googlechrome://",
            tier: 3
        ),
        // Tier 4 — China social
        HostAppEntry(
            bundleId: "com.sina.weibo",
            displayNameKey: "hostApp.weibo",
            returnURLString: "sinaweibo://",
            tier: 4
        ),
        HostAppEntry(
            bundleId: "com.xingin.discover",
            displayNameKey: "hostApp.xiaohongshu",
            returnURLString: "xhsdiscover://",
            tier: 4
        )
    ]

    private static let byBundleId: [String: HostAppEntry] = {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.bundleId, $0) })
    }()

    public static func lookup(bundleId: String?) -> HostAppEntry? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        return byBundleId[bundleId]
    }

    /// URL schemes declared in `LSApplicationQueriesSchemes` for `canOpenURL`.
    public static var querySchemes: [String] {
        Array(
            Set(
                entries.compactMap { entry -> String? in
                    guard let url = entry.returnURL, let scheme = url.scheme else { return nil }
                    return scheme
                }
            )
        ).sorted()
    }
}
