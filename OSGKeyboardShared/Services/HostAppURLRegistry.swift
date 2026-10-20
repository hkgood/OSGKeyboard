// HostAppURLRegistry.swift
// OSGKeyboard · Shared
//
// Public URL-scheme whitelist for returning to a known host app after a
// cold-start Flow session handoff. One bundle id maps to one preferred URL.
//
// Bundle ids are checked against the App Store lookup API. URL schemes have no
// public source of truth; a wrong one only makes the open fail (the user stays
// in OSG), it never sends the user to a different app.

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
    /// Curated whitelist: high-frequency typing hosts first, then the CN / US
    /// App Store top charts, then Apple system apps.
    public static let entries: [HostAppEntry] = [
        // Tier 1 — China IM / work
        app("com.tencent.xin", "wechat", "weixin://", tier: 1),
        app("com.tencent.mqq", "qq", "mqq://", tier: 1),
        app("com.tencent.ww", "wecom", "wxwork://", tier: 1),
        app("com.laiwang.DingTalk", "dingtalk", "dingtalk://", tier: 1),
        app("com.bytedance.ee.lark", "lark", "lark://", tier: 1),
        app("com.tencent.meeting", "tencentMeeting", "wemeet://", tier: 1),
        app("com.tencent.qqmail", "qqmail", "qqmail://", tier: 1),
        app("com.kingsoft.www.office.wpsoffice", "wps", "wpsoffice://", tier: 1),

        // Tier 2 — global IM / calls / dating
        app("ph.telegra.Telegraph", "telegram", "tg://", tier: 2),
        app("net.whatsapp.WhatsApp", "whatsapp", "whatsapp://", tier: 2),
        app("jp.naver.line", "line", "line://", tier: 2),
        app("com.facebook.Messenger", "messenger", "fb-messenger://", tier: 2),
        app("com.tinyspeck.chatlyio", "slack", "slack://", tier: 2),
        app("com.microsoft.skype.teams", "teams", "msteams://", tier: 2),
        app("com.hammerandchisel.discord", "discord", "discord://", tier: 2),
        app("org.whispersystems.signal", "signal", "sgnl://", tier: 2),
        app("com.iwilab.KakaoTalk", "kakaotalk", "kakaotalk://", tier: 2),
        app("com.viber", "viber", "viber://", tier: 2),
        app("vn.com.vng.zingalo", "zalo", "zalo://", tier: 2),
        app("us.zoom.videomeetings", "zoom", "zoomus://", tier: 2),
        app("com.cardify.tinder", "tinder", "tinder://", tier: 2),

        // Tier 3 — notes / mail / browser / office / AI
        app("notion.id", "notion", "notion://", tier: 3),
        app("net.shinyfrog.bear", "bear", "bear://", tier: 3),
        app("md.obsidian", "obsidian", "obsidian://", tier: 3),
        app("com.agiletortoise.Drafts5", "drafts", "drafts5://", tier: 3),
        app("com.culturedcode.ThingsiPhone", "things", "things://", tier: 3),
        app("com.todoist.ios", "todoist", "todoist://", tier: 3),
        app("com.evernote.iPhone.Evernote", "evernote", "evernote://", tier: 3),
        app("com.microsoft.onenote", "onenote", "onenote://", tier: 3),
        app("com.microsoft.Office.Word", "word", "ms-word://", tier: 3),
        app("com.microsoft.Office.Excel", "excel", "ms-excel://", tier: 3),
        app("com.google.Gmail", "gmail", "googlegmail://", tier: 3),
        app("com.microsoft.Office.Outlook", "outlook", "ms-outlook://", tier: 3),
        app("com.readdle.smartemail", "spark", "readdle-spark://", tier: 3),
        app("com.yahoo.Aerogram", "yahooMail", "ymail://", tier: 3),
        app("com.google.Docs", "googleDocs", "googledocs://", tier: 3),
        app("com.google.Sheets", "googleSheets", "googlesheets://", tier: 3),
        app("com.google.Drive", "googleDrive", "googledrive://", tier: 3),
        app("com.google.Translate", "googleTranslate", "googletranslate://", tier: 3),
        app("com.google.GoogleMobile", "google", "google://", tier: 3),
        app("com.google.chrome.ios", "chrome", "googlechrome://", tier: 3),
        app("org.mozilla.ios.Firefox", "firefox", "firefox://", tier: 3),
        app("com.microsoft.msedge", "edge", "microsoft-edge://", tier: 3),
        app("com.openai.chat", "chatgpt", "chatgpt://", tier: 3),
        app("com.anthropic.claude", "claude", "claude://", tier: 3),

        // Tier 4 — China social / content
        app("com.sina.weibo", "weibo", "sinaweibo://", tier: 4),
        app("com.xingin.discover", "xiaohongshu", "xhsdiscover://", tier: 4),
        app("com.zhihu.ios", "zhihu", "zhihu://", tier: 4),
        app("tv.danmaku.bilianime", "bilibili", "bilibili://", tier: 4),
        app("com.ss.iphone.ugc.Aweme", "douyin", "snssdk1128://", tier: 4),
        app("com.ss.iphone.ugc.aweme.lite", "douyinLite", "snssdk2329://", tier: 4),
        app("com.jiangjia.gif", "kuaishou", "kwai://", tier: 4),
        app("com.kuaishou.nebula", "kuaishouLite", "ksnebula://", tier: 4),
        app("com.ss.iphone.article.News", "toutiao", "snssdk141://", tier: 4),
        app("com.douban.frodo", "douban", "douban://", tier: 4),
        app("com.baidu.BaiduMobile", "baidu", "baiduboxapp://", tier: 4),
        app("com.youku.YouKu", "youku", "youku://", tier: 4),
        app("com.tencent.live4iphone", "tencentVideo", "tenvideo://", tier: 4),
        app("com.qiyi.iphone", "iqiyi", "iqiyi://", tier: 4),
        app("com.hunantv.imgotv", "mangoTV", "imgotv://", tier: 4),
        app("com.tencent.QQMusic", "qqMusic", "qqmusic://", tier: 4),
        app("com.netease.cloudmusic", "neteaseMusic", "orpheus://", tier: 4),
        app("com.kugou.kugou1002", "kugou", "kugouURL://", tier: 4),
        app("com.gemd.iting", "ximalaya", "iting://", tier: 4),
        app("com.tencent.weread", "weread", "weread://", tier: 4),

        // Tier 4 — global social / content
        app("com.facebook.Facebook", "facebook", "fb://", tier: 4),
        app("com.burbn.instagram", "instagram", "instagram://", tier: 4),
        app("com.atebits.Tweetie2", "x", "twitter://", tier: 4),
        app("com.burbn.barcelona", "threads", "barcelona://", tier: 4),
        app("com.toyopagroup.picaboo", "snapchat", "snapchat://", tier: 4),
        app("com.reddit.Reddit", "reddit", "reddit://", tier: 4),
        app("pinterest", "pinterest", "pinterest://", tier: 4),
        app("com.zhiliaoapp.musically", "tiktok", "tiktok://", tier: 4),
        app("com.google.ios.youtube", "youtube", "youtube://", tier: 4),
        app("com.linkedin.LinkedIn", "linkedin", "linkedin://", tier: 4),
        app("com.tumblr.tumblr", "tumblr", "tumblr://", tier: 4),
        app("tv.twitch", "twitch", "twitch://", tier: 4),
        app("com.spotify.client", "spotify", "spotify://", tier: 4),
        app("com.netflix.Netflix", "netflix", "nflx://", tier: 4),
        app("com.lemon.lvoverseas", "capcut", "capcut://", tier: 4),
        app("com.duolingo.DuolingoMobile", "duolingo", "duolingo://", tier: 4),

        // Tier 5 — China shopping / local services / travel / finance
        app("com.taobao.taobao4iphone", "taobao", "taobao://", tier: 5),
        app("com.taobao.tmall", "tmall", "tmall://", tier: 5),
        app("com.360buy.jdmobile", "jd", "openapp.jdmobile://", tier: 5),
        app("com.xunmeng.pinduoduo", "pinduoduo", "pinduoduo://", tier: 5),
        app("com.taobao.fleamarket", "xianyu", "fleamarket://", tier: 5),
        app("com.alibaba.wireless", "alibaba1688", "wireless1688://", tier: 5),
        app("com.vipshop.iphone", "vipshop", "vipshop://", tier: 5),
        app("com.meituan.imeituan", "meituan", "imeituan://", tier: 5),
        app("com.meituan.itakeaway", "meituanWaimai", "meituanwaimai://", tier: 5),
        app("me.ele.ios.eleme", "eleme", "eleme://", tier: 5),
        app("com.dianping.dpscope", "dianping", "dianping://", tier: 5),
        app("com.taofang.iphone", "wuba", "wbmain://", tier: 5),
        app("com.xiaojukeji.didi", "didi", "diditaxi://", tier: 5),
        app("com.autonavi.amap", "amap", "iosamap://", tier: 5),
        app("com.baidu.map", "baiduMap", "baidumap://", tier: 5),
        app("com.tencent.sosomap", "tencentMap", "qqmap://", tier: 5),
        app("ctrip.com", "ctrip", "ctrip://", tier: 5),
        app("com.baidu.netdisk", "baiduNetdisk", "baiduyun://", tier: 5),
        app("com.ucweb.iphone.lowversion", "ucBrowser", "ucbrowser://", tier: 5),
        app("com.tencent.mttlite", "qqBrowser", "mttbrowser://", tier: 5),
        app("com.alipay.iphoneclient", "alipay", "alipay://", tier: 5),
        app("com.unionpay.chsp", "unionpay", "upwallet://", tier: 5),
        app("com.cmbchina.MPBBank", "cmb", "cmbmobilebank://", tier: 5),
        app("com.ccb.ccbDemo", "ccb", "ccbmobilebank://", tier: 5),
        app("com.bankabc.iphonerelease", "abc", "bankabc://", tier: 5),

        // Tier 5 — US shopping / local services / finance
        app("com.amazon.Amazon", "amazon", "com.amazon.mobile.shopping://", tier: 5),
        app("com.walmart.electronics", "walmart", "walmart://", tier: 5),
        app("com.ebay.iphone", "ebay", "ebay://", tier: 5),
        app("com.alibaba.iAliexpress", "aliexpress", "aliexpress://", tier: 5),
        app("com.ubercab.UberClient", "uber", "uber://", tier: 5),
        app("com.zimride.instant", "lyft", "lyft://", tier: 5),
        app("doordash.DoorDashConsumer", "doordash", "doordash://", tier: 5),
        app("com.airbnb.app", "airbnb", "airbnb://", tier: 5),
        app("com.google.Maps", "googleMaps", "comgooglemaps://", tier: 5),
        app("com.yourcompany.PPClient", "paypal", "paypal://", tier: 5),
        app("net.kortina.labs.Venmo", "venmo", "venmo://", tier: 5),
        app("com.squareup.cash", "cashApp", "cashme://", tier: 5),

        // Tier 6 — Apple system apps. Safari has no scheme that reopens the
        // current tab (every https/x-web-search URL opens a new page), so it is
        // deliberately absent.
        app("com.apple.MobileSMS", "messages", "messages://", tier: 6),
        app("com.apple.mobilenotes", "notes", "mobilenotes://", tier: 6),
        app("com.apple.mobilemail", "mail", "message://", tier: 6),
        app("com.apple.reminders", "reminders", "x-apple-reminderkit://", tier: 6),
        app("com.apple.mobilecal", "calendar", "calshow://", tier: 6),
        app("com.apple.shortcuts", "shortcuts", "shortcuts://", tier: 6),
        app("com.apple.DocumentsApp", "files", "shareddocuments://", tier: 6),
        app("com.apple.Maps", "maps", "maps://", tier: 6),
        app("com.apple.AppStore", "appStore", "itms-apps://", tier: 6)
    ]

    private static func app(_ bundleId: String, _ name: String, _ url: String, tier: Int) -> HostAppEntry {
        HostAppEntry(bundleId: bundleId, displayNameKey: "hostApp.\(name)", returnURLString: url, tier: tier)
    }

    private static let byBundleId: [String: HostAppEntry] = {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.bundleId, $0) })
    }()

    public static func lookup(bundleId: String?) -> HostAppEntry? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        return byBundleId[bundleId]
    }

    /// OSG's own targets (host app, keyboard, Mac) are never a return destination.
    public static func isOwnBundleId(_ bundleId: String) -> Bool {
        bundleId == ownBundleIdRoot || bundleId.hasPrefix(ownBundleIdRoot + ".")
    }

    private static let ownBundleIdRoot = "com.osgkeyboard"
}
