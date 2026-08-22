// AIHintStore.swift
// OSGKeyboard · Shared
//
// Reads/writes host-ready hint packs from App Group. Keyboard only reads.

import Foundation

public enum AIHintStore: Sendable {
    public static let refreshInterval: TimeInterval = 12 * 60 * 60
    /// Without a feed `expiresAt`, a pack still stops being served once it is
    /// this old — stale hot topics are worse than the evergreen local catalog.
    public static let maximumPackAge: TimeInterval = 48 * 60 * 60

    public static func loadReadyPack(
        locale: String,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> AIHintPack? {
        guard let defaults,
              let data = defaults.data(forKey: AIHintAppGroupKeys.readyPackKey(locale: locale))
        else { return nil }
        return try? JSONDecoder().decode(AIHintPack.self, from: data)
    }

    public static func saveReadyPack(
        _ pack: AIHintPack,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        guard let defaults else { return }
        var copy = pack
        copy.refreshedAt = copy.refreshedAt ?? Date()
        guard let data = try? JSONEncoder().encode(copy) else { return }
        defaults.set(data, forKey: AIHintAppGroupKeys.readyPackKey(locale: pack.locale))
        defaults.set(
            (copy.refreshedAt ?? Date()).timeIntervalSince1970,
            forKey: AIHintAppGroupKeys.lastSuccessKey(locale: pack.locale)
        )
        defaults.synchronize()
    }

    public static func loadManifest(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> AIHintManifest? {
        guard let data = defaults?.data(forKey: AIHintAppGroupKeys.manifest) else {
            return nil
        }
        return try? JSONDecoder().decode(AIHintManifest.self, from: data)
    }

    public static func saveManifest(
        _ manifest: AIHintManifest,
        etag: String?,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        guard let defaults,
              let data = try? JSONEncoder().encode(manifest) else { return }
        defaults.set(data, forKey: AIHintAppGroupKeys.manifest)
        setManifestETag(etag, defaults: defaults)
        defaults.synchronize()
    }

    public static func manifestETag(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> String? {
        defaults?.string(forKey: AIHintAppGroupKeys.manifestETag)
    }

    public static func setManifestETag(
        _ etag: String?,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        guard let defaults else { return }
        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: AIHintAppGroupKeys.manifestETag)
        } else {
            defaults.removeObject(forKey: AIHintAppGroupKeys.manifestETag)
        }
    }

    public static func packETag(
        locale: String,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> String? {
        defaults?.string(forKey: AIHintAppGroupKeys.packETagKey(locale: locale))
    }

    public static func setPackETag(
        _ etag: String?,
        locale: String,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        guard let defaults else { return }
        let key = AIHintAppGroupKeys.packETagKey(locale: locale)
        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public static func lastSuccessAt(
        locale: String,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> Date? {
        let key = AIHintAppGroupKeys.lastSuccessKey(locale: locale)
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    public static func markAttempt(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        defaults?.set(Date().timeIntervalSince1970, forKey: AIHintAppGroupKeys.lastAttemptAt)
    }

    /// One stale locale is enough to schedule a refresh pass.
    public static func shouldRefresh(
        now: Date = Date(),
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> Bool {
        AIHintFeedEndpoints.supportedLocales.contains { locale in
            shouldRefresh(locale: locale, now: now, defaults: defaults)
        }
    }

    public static func shouldRefresh(
        locale: String,
        now: Date = Date(),
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> Bool {
        guard let last = lastSuccessAt(locale: locale, defaults: defaults) else { return true }
        return now.timeIntervalSince(last) >= refreshInterval
    }

    /// Keyboard-facing pack: fresh ready remote/local merge, else built-in catalog.
    public static func resolvedPack(
        locale: String,
        now: Date = Date(),
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> AIHintPack {
        if let ready = loadReadyPack(locale: locale, defaults: defaults),
           !ready.cards.isEmpty,
           !isExpired(ready, now: now) {
            return ready
        }
        return AIHintPack(
            locale: locale,
            cards: AIHintLocalCatalog.cards(locale: locale),
            refreshedAt: nil
        )
    }

    /// The feed's `expiresAt` is authoritative; `maximumPackAge` is the fallback.
    static func isExpired(_ pack: AIHintPack, now: Date = Date()) -> Bool {
        if let expiresAt = pack.expiresAt, let deadline = date(fromISO8601: expiresAt) {
            return now > deadline
        }
        guard let refreshedAt = pack.refreshedAt else { return false }
        return now.timeIntervalSince(refreshedAt) >= maximumPackAge
    }

    private static func date(fromISO8601 value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
