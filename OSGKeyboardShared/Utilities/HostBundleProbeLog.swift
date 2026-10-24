// HostBundleProbeLog.swift
// OSGKeyboard · Shared
//
// 临时调试：键盘扩展把 arbiter 回调识别到的宿主 bundle ID 写进 App Group，
// 主 App 首页读出来展示，用于真机验证 iOS 26.4+ 宿主识别方案。验证结束后删除。

#if DEBUG
import Foundation

public enum HostBundleProbeLog {
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        /// `appear`：键盘弹出（随后主动触发一次回调）；`arbiter`：系统回调。
        public let event: String
        /// 回调里读到的宿主 bundle ID；读不到时为 nil。
        public let bundleId: String?
        /// 回调参数的类名等辅助信息，方便字段失效时排查。
        public let detail: String?
    }

    private static let key = "debug.hostBundleProbe.entries"
    private static let limit = 40

    /// 新记录插在最前面，只保留最近 `limit` 条。
    public static func append(event: String, bundleId: String?, detail: String? = nil) {
        guard let defaults = AppGroup.defaultsIfAvailable else { return }
        let entry = Entry(id: UUID(), date: Date(), event: event, bundleId: bundleId, detail: detail)
        let updated = Array(([entry] + entries()).prefix(limit))
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: key)
    }

    /// 按时间倒序返回。
    public static func entries() -> [Entry] {
        guard let data = AppGroup.defaultsIfAvailable?.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    public static func clear() {
        AppGroup.defaultsIfAvailable?.removeObject(forKey: key)
    }
}
#endif
