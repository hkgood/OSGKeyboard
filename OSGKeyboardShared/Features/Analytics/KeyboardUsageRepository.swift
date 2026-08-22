// KeyboardUsageRepository.swift
// OSGKeyboard · Shared
//
// Cross-process daily counters and immutable summary outbox. SQLite WAL plus
// BEGIN IMMEDIATE prevents lost updates and duplicate day finalization.

import Foundation
import SQLite3

public struct KeyboardUsageRepositoryConfiguration: Sendable {
    public static let defaultDatabaseFilename = "keyboard-usage.sqlite3"

    public let databaseURL: URL?
    public let busyTimeoutMilliseconds: Int32

    public init(
        databaseURL: URL?,
        busyTimeoutMilliseconds: Int32 = 250
    ) {
        self.databaseURL = databaseURL
        self.busyTimeoutMilliseconds = max(0, busyTimeoutMilliseconds)
    }

    public static func appGroupDefault(
        appGroupIdentifier: String = AppGroup.identifier
    ) -> Self {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        let directory = container?.appendingPathComponent(
            "Library/Application Support/Analytics",
            isDirectory: true
        )
        return Self(
            databaseURL: directory?.appendingPathComponent(defaultDatabaseFilename)
        )
    }
}

public struct KeyboardUsageDailyDiagnostic: Equatable, Sendable {
    public let summaryDate: String
    public let chineseCharacterCount: Int
    public let englishCharacterCount: Int
    public let otherCharacterCount: Int
    public let inputSessionCount: Int
    public let chineseOnlySessionCount: Int
    public let englishOnlySessionCount: Int
    public let mixedLanguageSessionCount: Int
    public let otherOnlySessionCount: Int
}

public struct KeyboardUsageOutboxDiagnostic: Equatable, Sendable {
    public let summaryDate: String
    public let clientSummaryID: UUID?
    public let attemptCount: Int
    public let nextAttemptAt: Date
    public let statusCode: Int?
}

public struct KeyboardUsageRepositoryDebugSnapshot: Sendable {
    public let isAvailable: Bool
    public let daily: [KeyboardUsageDailyDiagnostic]
    public let pending: [KeyboardUsageOutboxDiagnostic]
    public let quarantined: [KeyboardUsageOutboxDiagnostic]
}

struct KeyboardUsageLeasedSummary: Sendable {
    let rowID: Int64
    let payload: Data
    let attemptCount: Int
}

struct KeyboardUsageLeasedBatch: Sendable {
    let leaseID: String
    let installationID: UUID
    let summaries: [KeyboardUsageLeasedSummary]
}

public actor KeyboardUsageRepository {
    private enum MetadataKey {
        static let uploadLeaseOwner = "uploadLeaseOwner"
        static let uploadLeaseExpiresAt = "uploadLeaseExpiresAt"
    }

    private static let maximumSessionCount = 100_000

    private let configuration: KeyboardUsageRepositoryConfiguration
    private let clock: any AnalyticsWallClock
    private let uuidGenerator: any AnalyticsUUIDGenerating
    private var database: SQLiteDatabase?
    private var isDatabaseAccessSuspended = false

    public init(
        configuration: KeyboardUsageRepositoryConfiguration = .appGroupDefault(),
        clock: any AnalyticsWallClock = SystemAnalyticsWallClock(),
        uuidGenerator: any AnalyticsUUIDGenerating = SystemAnalyticsUUIDGenerator()
    ) {
        self.configuration = configuration
        self.clock = clock
        self.uuidGenerator = uuidGenerator
    }

    /// Re-enables process-local access before foreground or BGTask work.
    public func resumeDatabaseAccess() {
        isDatabaseAccessSuspended = false
    }

    /// Closes the process-local connection after all earlier actor work.
    /// Keyboard-extension recording uses a different runtime and is unaffected.
    public func suspendDatabaseAccess() {
        isDatabaseAccessSuspended = true
        database = nil
    }

    public func record(
        counts: KeyboardUsageCharacterCounts,
        sessionID: UUID,
        installationID: UUID,
        occurredAt: Date,
        environment: AnalyticsEnvironment
    ) {
        guard !counts.isEmpty, let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                let summaryDate = KeyboardUsageUTCDate.string(from: occurredAt)
                try upsertCharacterCounts(
                    counts,
                    summaryDate: summaryDate,
                    installationID: installationID,
                    environment: environment,
                    database: database
                )
                try updateSession(
                    counts: counts,
                    sessionID: sessionID,
                    summaryDate: summaryDate,
                    installationID: installationID,
                    database: database
                )
                try finalizeCompletedDays(
                    today: KeyboardUsageUTCDate.string(from: clock.now()),
                    database: database
                )
            }
        }
    }

    public func finalizeCompletedDays() {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                try finalizeCompletedDays(
                    today: KeyboardUsageUTCDate.string(from: clock.now()),
                    database: database
                )
            }
        }
    }

    public func clearAll() {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                try database.execute("DELETE FROM usage_session_fragments")
                try database.execute("DELETE FROM usage_daily_counters")
                try database.execute("DELETE FROM usage_outbox")
                try database.execute("DELETE FROM usage_quarantine")
                try database.execute("DELETE FROM usage_metadata")
            }
        }
    }

    public func debugSnapshot() -> KeyboardUsageRepositoryDebugSnapshot {
        guard let database = openDatabaseIfNeeded() else {
            return Self.unavailableSnapshot
        }
        do {
            return try database.immediateTransaction {
                KeyboardUsageRepositoryDebugSnapshot(
                    isAvailable: true,
                    daily: try dailyDiagnostics(database),
                    pending: try outboxDiagnostics(
                        table: "usage_outbox",
                        includesStatus: false,
                        database: database
                    ),
                    quarantined: try outboxDiagnostics(
                        table: "usage_quarantine",
                        includesStatus: true,
                        database: database
                    )
                )
            }
        } catch {
            return Self.unavailableSnapshot
        }
    }

    func debugPayload(rowID: Int64, quarantined: Bool = false) -> Data? {
        guard !quarantined else { return nil }
        guard let database = openDatabaseIfNeeded() else { return nil }
        return try? database.query(
            "SELECT payload FROM usage_outbox WHERE id = ?",
            bindings: [.int64(rowID)]
        ).first?.data(at: 0)
    }

    func leaseBatch(
        ownerID: String,
        configuration upload: KeyboardUsageUploadConfiguration
    ) -> KeyboardUsageLeasedBatch? {
        guard let database = openDatabaseIfNeeded() else { return nil }
        do {
            return try database.immediateTransaction {
                let now = clock.now()
                let nowInterval = now.timeIntervalSince1970
                let today = KeyboardUsageUTCDate.string(from: now)
                try finalizeCompletedDays(today: today, database: database)
                try quarantineExpiredSummaries(today: today, database: database)
                try releaseExpiredLeases(now: nowInterval, database: database)
                guard try acquireGlobalLease(
                    ownerID: ownerID,
                    expiresAt: nowInterval + upload.globalLeaseDuration,
                    now: nowInterval,
                    database: database
                ) else {
                    return nil
                }

                guard let installationText = try database.query(
                    """
                    SELECT installation_id
                    FROM usage_outbox
                    WHERE next_attempt_at <= ? AND lease_id IS NULL
                    ORDER BY summary_date ASC
                    LIMIT 1
                    """,
                    bindings: [.double(nowInterval)]
                ).first?.text(at: 0),
                let installationID = UUID(uuidString: installationText) else {
                    try clearGlobalLease(database)
                    return nil
                }

                let rows = try database.query(
                    """
                    SELECT id, payload, attempt_count
                    FROM usage_outbox
                    WHERE installation_id = ?
                      AND next_attempt_at <= ?
                      AND lease_id IS NULL
                    ORDER BY summary_date ASC
                    LIMIT ?
                    """,
                    bindings: [
                        .text(installationText),
                        .double(nowInterval),
                        .int64(Int64(upload.maximumBatchCount))
                    ]
                )
                let summaries = rows.compactMap { row -> KeyboardUsageLeasedSummary? in
                    guard let rowID = row.int64(at: 0),
                          let payload = row.data(at: 1),
                          let attemptCount = row.int64(at: 2) else {
                        return nil
                    }
                    return KeyboardUsageLeasedSummary(
                        rowID: rowID,
                        payload: payload,
                        attemptCount: Int(attemptCount)
                    )
                }
                guard !summaries.isEmpty else {
                    try clearGlobalLease(database)
                    return nil
                }

                let leaseID = uuidGenerator.makeUUID().uuidString.lowercased()
                let leaseExpiry = nowInterval + upload.summaryLeaseDuration
                for summary in summaries {
                    try database.execute(
                        """
                        UPDATE usage_outbox
                        SET lease_id = ?, lease_expires_at = ?
                        WHERE id = ? AND lease_id IS NULL
                        """,
                        bindings: [
                            .text(leaseID),
                            .double(leaseExpiry),
                            .int64(summary.rowID)
                        ]
                    )
                }
                return KeyboardUsageLeasedBatch(
                    leaseID: leaseID,
                    installationID: installationID,
                    summaries: summaries
                )
            }
        } catch {
            return nil
        }
    }

    func renewLease(
        ownerID: String,
        leaseID: String,
        configuration upload: KeyboardUsageUploadConfiguration
    ) -> Bool {
        guard let database = openDatabaseIfNeeded() else { return false }
        do {
            return try database.immediateTransaction {
                guard try metadata(
                    MetadataKey.uploadLeaseOwner,
                    database: database
                ) == ownerID else {
                    return false
                }
                let now = clock.now().timeIntervalSince1970
                try setMetadata(
                    String(now + upload.globalLeaseDuration),
                    key: MetadataKey.uploadLeaseExpiresAt,
                    database: database
                )
                try database.execute(
                    """
                    UPDATE usage_outbox
                    SET lease_expires_at = ?
                    WHERE lease_id = ?
                    """,
                    bindings: [
                        .double(now + upload.summaryLeaseDuration),
                        .text(leaseID)
                    ]
                )
                // Account rotation clears the outbox before a new bearer may
                // be used. A leased in-memory batch is valid only while at
                // least one matching row still exists in SQLite.
                guard database.changes > 0 else {
                    try clearGlobalLease(database)
                    return false
                }
                return true
            }
        } catch {
            return false
        }
    }

    func complete(rowIDs: [Int64], leaseID: String) -> Bool {
        guard let database = openDatabaseIfNeeded(), !rowIDs.isEmpty else {
            return false
        }
        do {
            return try database.immediateTransaction {
                var deleted = 0
                for rowID in rowIDs {
                    try database.execute(
                        "DELETE FROM usage_outbox WHERE id = ? AND lease_id = ?",
                        bindings: [.int64(rowID), .text(leaseID)]
                    )
                    deleted += Int(database.changes)
                }
                return deleted == rowIDs.count
            }
        } catch {
            return false
        }
    }

    func scheduleRetry(
        summaries: [KeyboardUsageLeasedSummary],
        leaseID: String,
        delay: TimeInterval
    ) {
        guard let database = openDatabaseIfNeeded(), !summaries.isEmpty else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                let nextAttempt = clock.now().addingTimeInterval(max(0, delay))
                    .timeIntervalSince1970
                for summary in summaries {
                    try database.execute(
                        """
                        UPDATE usage_outbox
                        SET attempt_count = attempt_count + 1,
                            next_attempt_at = ?,
                            lease_id = NULL,
                            lease_expires_at = NULL
                        WHERE id = ? AND lease_id = ?
                        """,
                        bindings: [
                            .double(nextAttempt),
                            .int64(summary.rowID),
                            .text(leaseID)
                        ]
                    )
                }
            }
        }
    }

    func quarantine(
        rowIDs: [Int64],
        leaseID: String,
        statusCode: Int
    ) {
        guard let database = openDatabaseIfNeeded(), !rowIDs.isEmpty else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                for rowID in rowIDs {
                    try moveToQuarantine(
                        rowID: rowID,
                        leaseID: leaseID,
                        statusCode: statusCode,
                        database: database
                    )
                }
            }
        }
    }

    func release(
        summaries: [KeyboardUsageLeasedSummary],
        leaseID: String
    ) {
        guard let database = openDatabaseIfNeeded(), !summaries.isEmpty else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                for summary in summaries {
                    try database.execute(
                        """
                        UPDATE usage_outbox
                        SET lease_id = NULL, lease_expires_at = NULL
                        WHERE id = ? AND lease_id = ?
                        """,
                        bindings: [.int64(summary.rowID), .text(leaseID)]
                    )
                }
            }
        }
    }

    func releaseGlobalLease(ownerID: String) {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                guard try metadata(
                    MetadataKey.uploadLeaseOwner,
                    database: database
                ) == ownerID else {
                    return
                }
                try clearGlobalLease(database)
            }
        }
    }

    private func upsertCharacterCounts(
        _ counts: KeyboardUsageCharacterCounts,
        summaryDate: String,
        installationID: UUID,
        environment: AnalyticsEnvironment,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO usage_daily_counters (
                installation_id, summary_date,
                chinese_count, english_count, other_count,
                input_session_count, chinese_only_count, english_only_count,
                mixed_count, other_only_count, app_version, os_version
            ) VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0, 0, ?, ?)
            ON CONFLICT(installation_id, summary_date) DO UPDATE SET
                chinese_count = MIN(1000000, chinese_count + excluded.chinese_count),
                english_count = MIN(1000000, english_count + excluded.english_count),
                other_count = MIN(1000000, other_count + excluded.other_count)
            """,
            bindings: [
                .text(installationID.uuidString.lowercased()),
                .text(summaryDate),
                .int64(Int64(counts.chinese)),
                .int64(Int64(counts.english)),
                .int64(Int64(counts.other)),
                .text(environment.appVersion),
                .text(environment.osVersion)
            ]
        )
    }

    private func updateSession(
        counts: KeyboardUsageCharacterCounts,
        sessionID: UUID,
        summaryDate: String,
        installationID: UUID,
        database: SQLiteDatabase
    ) throws {
        let installationText = installationID.uuidString.lowercased()
        let sessionText = sessionID.uuidString.lowercased()
        let rows = try database.query(
            """
            SELECT classification, counted
            FROM usage_session_fragments
            WHERE installation_id = ? AND summary_date = ? AND session_id = ?
            """,
            bindings: [
                .text(installationText),
                .text(summaryDate),
                .text(sessionText)
            ]
        )
        let incoming = KeyboardUsageSessionClassification(counts: counts)
        if let row = rows.first,
           let rawClassification = row.int64(at: 0),
           let previous = KeyboardUsageSessionClassification(
            rawValue: Int(rawClassification)
           ),
           let countedValue = row.int64(at: 1) {
            let merged = previous.merging(counts)
            guard merged != previous else { return }
            try database.execute(
                """
                UPDATE usage_session_fragments
                SET classification = ?
                WHERE installation_id = ? AND summary_date = ? AND session_id = ?
                """,
                bindings: [
                    .int64(Int64(merged.rawValue)),
                    .text(installationText),
                    .text(summaryDate),
                    .text(sessionText)
                ]
            )
            if countedValue == 1 {
                try database.execute(
                    """
                    UPDATE usage_daily_counters
                    SET \(Self.column(for: previous)) = \(Self.column(for: previous)) - 1,
                        \(Self.column(for: merged)) = \(Self.column(for: merged)) + 1
                    WHERE installation_id = ? AND summary_date = ?
                    """,
                    bindings: [.text(installationText), .text(summaryDate)]
                )
            }
            return
        }

        let inputSessionCount = try database.query(
            """
            SELECT input_session_count
            FROM usage_daily_counters
            WHERE installation_id = ? AND summary_date = ?
            """,
            bindings: [.text(installationText), .text(summaryDate)]
        ).first?.int64(at: 0) ?? 0
        let counted = inputSessionCount < Int64(Self.maximumSessionCount)
        try database.execute(
            """
            INSERT OR IGNORE INTO usage_session_fragments (
                installation_id, summary_date, session_id, classification, counted
            ) VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(installationText),
                .text(summaryDate),
                .text(sessionText),
                .int64(Int64(incoming.rawValue)),
                .int64(counted ? 1 : 0)
            ]
        )
        guard database.changes == 1, counted else { return }
        try database.execute(
            """
            UPDATE usage_daily_counters
            SET input_session_count = input_session_count + 1,
                \(Self.column(for: incoming)) = \(Self.column(for: incoming)) + 1
            WHERE installation_id = ? AND summary_date = ?
            """,
            bindings: [.text(installationText), .text(summaryDate)]
        )
    }

    private func finalizeCompletedDays(
        today: String,
        database: SQLiteDatabase
    ) throws {
        let rows = try database.query(
            """
            SELECT installation_id, summary_date,
                   chinese_count, english_count, other_count,
                   input_session_count, chinese_only_count, english_only_count,
                   mixed_count, other_only_count, app_version, os_version
            FROM usage_daily_counters
            WHERE summary_date < ?
            ORDER BY summary_date ASC
            """,
            bindings: [.text(today)]
        )
        for row in rows {
            guard let installationText = row.text(at: 0),
                  UUID(uuidString: installationText) != nil,
                  let summaryDate = row.text(at: 1),
                  let chinese = row.int64(at: 2),
                  let english = row.int64(at: 3),
                  let other = row.int64(at: 4),
                  let sessions = row.int64(at: 5),
                  let chineseOnly = row.int64(at: 6),
                  let englishOnly = row.int64(at: 7),
                  let mixed = row.int64(at: 8),
                  let otherOnly = row.int64(at: 9),
                  let appVersion = row.text(at: 10),
                  let osVersion = row.text(at: 11) else {
                continue
            }
            let summary = try KeyboardUsageSummary(
                clientSummaryId: uuidGenerator.makeUUID(),
                summaryDate: summaryDate,
                chineseCharacterCount: Int(chinese),
                englishCharacterCount: Int(english),
                otherCharacterCount: Int(other),
                inputSessionCount: Int(sessions),
                chineseOnlySessionCount: Int(chineseOnly),
                englishOnlySessionCount: Int(englishOnly),
                mixedLanguageSessionCount: Int(mixed),
                otherOnlySessionCount: Int(otherOnly),
                appVersion: appVersion,
                osVersion: osVersion
            )
            let payload = try AnalyticsCanonicalJSON.encode(summary)
            try database.execute(
                """
                INSERT OR IGNORE INTO usage_outbox (
                    installation_id, summary_date, client_summary_id, payload,
                    attempt_count, next_attempt_at, lease_id, lease_expires_at,
                    created_at
                ) VALUES (?, ?, ?, ?, 0, 0, NULL, NULL, ?)
                """,
                bindings: [
                    .text(installationText),
                    .text(summaryDate),
                    .text(summary.clientSummaryId.uuidString.lowercased()),
                    .blob(payload),
                    .double(clock.now().timeIntervalSince1970)
                ]
            )
            try database.execute(
                """
                DELETE FROM usage_session_fragments
                WHERE installation_id = ? AND summary_date = ?
                """,
                bindings: [.text(installationText), .text(summaryDate)]
            )
            try database.execute(
                """
                DELETE FROM usage_daily_counters
                WHERE installation_id = ? AND summary_date = ?
                """,
                bindings: [.text(installationText), .text(summaryDate)]
            )
        }
    }

    private func quarantineExpiredSummaries(
        today: String,
        database: SQLiteDatabase
    ) throws {
        guard let oldest = KeyboardUsageUTCDate.oldestAcceptedDate(
            relativeTo: today
        ) else {
            return
        }
        let rowIDs = try database.query(
            """
            SELECT id FROM usage_outbox
            WHERE summary_date < ? AND lease_id IS NULL
            """,
            bindings: [.text(oldest)]
        ).compactMap { $0.int64(at: 0) }
        for rowID in rowIDs {
            try moveToQuarantine(
                rowID: rowID,
                leaseID: nil,
                statusCode: 0,
                database: database
            )
        }
    }

    private func moveToQuarantine(
        rowID: Int64,
        leaseID: String?,
        statusCode: Int,
        database: SQLiteDatabase
    ) throws {
        var clause = ""
        var selectBindings: [SQLiteBinding] = [
            .int64(Int64(statusCode)),
            .double(clock.now().timeIntervalSince1970),
            .int64(rowID)
        ]
        var deleteBindings: [SQLiteBinding] = [.int64(rowID)]
        if let leaseID {
            clause = " AND lease_id = ?"
            selectBindings.append(.text(leaseID))
            deleteBindings.append(.text(leaseID))
        }
        try database.execute(
            """
            INSERT OR IGNORE INTO usage_quarantine (
                summary_date, attempt_count, status_code, quarantined_at
            )
            SELECT summary_date, attempt_count, ?, ?
            FROM usage_outbox
            WHERE id = ?\(clause)
            """,
            bindings: selectBindings
        )
        try database.execute(
            "DELETE FROM usage_outbox WHERE id = ?\(clause)",
            bindings: deleteBindings
        )
    }

    private static func column(
        for classification: KeyboardUsageSessionClassification
    ) -> String {
        switch classification {
        case .chineseOnly:
            return "chinese_only_count"
        case .englishOnly:
            return "english_only_count"
        case .mixedLanguage:
            return "mixed_count"
        case .otherOnly:
            return "other_only_count"
        }
    }

    private func acquireGlobalLease(
        ownerID: String,
        expiresAt: TimeInterval,
        now: TimeInterval,
        database: SQLiteDatabase
    ) throws -> Bool {
        let owner = try metadata(MetadataKey.uploadLeaseOwner, database: database)
        let expiry = try metadata(
            MetadataKey.uploadLeaseExpiresAt,
            database: database
        ).flatMap(TimeInterval.init) ?? 0
        guard owner == nil || owner == ownerID || expiry <= now else { return false }
        try setMetadata(
            ownerID,
            key: MetadataKey.uploadLeaseOwner,
            database: database
        )
        try setMetadata(
            String(expiresAt),
            key: MetadataKey.uploadLeaseExpiresAt,
            database: database
        )
        return true
    }

    private func releaseExpiredLeases(
        now: TimeInterval,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            UPDATE usage_outbox
            SET lease_id = NULL, lease_expires_at = NULL
            WHERE lease_expires_at IS NOT NULL AND lease_expires_at <= ?
            """,
            bindings: [.double(now)]
        )
    }

    private func clearGlobalLease(_ database: SQLiteDatabase) throws {
        try database.execute(
            "DELETE FROM usage_metadata WHERE key IN (?, ?)",
            bindings: [
                .text(MetadataKey.uploadLeaseOwner),
                .text(MetadataKey.uploadLeaseExpiresAt)
            ]
        )
    }

    private func metadata(
        _ key: String,
        database: SQLiteDatabase
    ) throws -> String? {
        try database.query(
            "SELECT value FROM usage_metadata WHERE key = ?",
            bindings: [.text(key)]
        ).first?.text(at: 0)
    }

    private func setMetadata(
        _ value: String,
        key: String,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO usage_metadata(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            bindings: [.text(key), .text(value)]
        )
    }

    private func dailyDiagnostics(
        _ database: SQLiteDatabase
    ) throws -> [KeyboardUsageDailyDiagnostic] {
        try database.query(
            """
            SELECT summary_date, chinese_count, english_count, other_count,
                   input_session_count, chinese_only_count, english_only_count,
                   mixed_count, other_only_count
            FROM usage_daily_counters
            ORDER BY summary_date ASC
            """
        ).compactMap { row in
            guard let date = row.text(at: 0),
                  let chinese = row.int64(at: 1),
                  let english = row.int64(at: 2),
                  let other = row.int64(at: 3),
                  let sessions = row.int64(at: 4),
                  let chineseOnly = row.int64(at: 5),
                  let englishOnly = row.int64(at: 6),
                  let mixed = row.int64(at: 7),
                  let otherOnly = row.int64(at: 8) else {
                return nil
            }
            return KeyboardUsageDailyDiagnostic(
                summaryDate: date,
                chineseCharacterCount: Int(chinese),
                englishCharacterCount: Int(english),
                otherCharacterCount: Int(other),
                inputSessionCount: Int(sessions),
                chineseOnlySessionCount: Int(chineseOnly),
                englishOnlySessionCount: Int(englishOnly),
                mixedLanguageSessionCount: Int(mixed),
                otherOnlySessionCount: Int(otherOnly)
            )
        }
    }

    private func outboxDiagnostics(
        table: String,
        includesStatus: Bool,
        database: SQLiteDatabase
    ) throws -> [KeyboardUsageOutboxDiagnostic] {
        let statusColumn = includesStatus ? "status_code" : "NULL"
        let nextAttemptColumn = includesStatus ? "quarantined_at" : "next_attempt_at"
        let identifierColumn = includesStatus ? "NULL" : "client_summary_id"
        return try database.query(
            """
            SELECT summary_date, \(identifierColumn), attempt_count,
                   \(nextAttemptColumn), \(statusColumn)
            FROM \(table)
            ORDER BY summary_date ASC
            """
        ).compactMap { row in
            guard let date = row.text(at: 0),
                  let attempts = row.int64(at: 2),
                  let nextAttempt = row.double(at: 3) else {
                return nil
            }
            return KeyboardUsageOutboxDiagnostic(
                summaryDate: date,
                clientSummaryID: row.text(at: 1).flatMap(UUID.init(uuidString:)),
                attemptCount: Int(attempts),
                nextAttemptAt: Date(timeIntervalSince1970: nextAttempt),
                statusCode: row.int64(at: 4).map(Int.init)
            )
        }
    }

    private func openDatabaseIfNeeded() -> SQLiteDatabase? {
        guard !isDatabaseAccessSuspended else { return nil }
        if let database { return database }
        guard let url = configuration.databaseURL else { return nil }
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: Self.directoryProtectionAttributes
        )
        // A second process can be setting WAL/schema pragmas during its first
        // open. Retry that short bootstrap race instead of dropping an input.
        for attempt in 0..<5 {
            do {
                let opened = try SQLiteDatabase(
                    url: url,
                    busyTimeoutMilliseconds: configuration.busyTimeoutMilliseconds
                )
                try migrate(opened)
                applyFileProtection(to: url)
                database = opened
                return opened
            } catch {
                guard attempt < 4 else { return nil }
                Thread.sleep(forTimeInterval: 0.01 * Double(attempt + 1))
            }
        }
        return nil
    }

    private func migrate(_ database: SQLiteDatabase) throws {
        let version = try database.scalarInt64("PRAGMA user_version") ?? 0
        guard version <= 1 else { return }
        guard version == 0 else { return }
        try database.immediateTransaction {
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_daily_counters (
                    installation_id TEXT NOT NULL,
                    summary_date TEXT NOT NULL,
                    chinese_count INTEGER NOT NULL CHECK(chinese_count BETWEEN 0 AND 1000000),
                    english_count INTEGER NOT NULL CHECK(english_count BETWEEN 0 AND 1000000),
                    other_count INTEGER NOT NULL CHECK(other_count BETWEEN 0 AND 1000000),
                    input_session_count INTEGER NOT NULL CHECK(input_session_count BETWEEN 0 AND 100000),
                    chinese_only_count INTEGER NOT NULL CHECK(chinese_only_count BETWEEN 0 AND 100000),
                    english_only_count INTEGER NOT NULL CHECK(english_only_count BETWEEN 0 AND 100000),
                    mixed_count INTEGER NOT NULL CHECK(mixed_count BETWEEN 0 AND 100000),
                    other_only_count INTEGER NOT NULL CHECK(other_only_count BETWEEN 0 AND 100000),
                    app_version TEXT NOT NULL,
                    os_version TEXT NOT NULL,
                    PRIMARY KEY(installation_id, summary_date),
                    CHECK(chinese_only_count + english_only_count + mixed_count
                          + other_only_count = input_session_count)
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_session_fragments (
                    installation_id TEXT NOT NULL,
                    summary_date TEXT NOT NULL,
                    session_id TEXT NOT NULL,
                    classification INTEGER NOT NULL CHECK(classification BETWEEN 0 AND 3),
                    counted INTEGER NOT NULL CHECK(counted IN (0, 1)),
                    PRIMARY KEY(installation_id, summary_date, session_id)
                ) WITHOUT ROWID
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_outbox (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    installation_id TEXT NOT NULL,
                    summary_date TEXT NOT NULL,
                    client_summary_id TEXT UNIQUE NOT NULL,
                    payload BLOB NOT NULL,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    next_attempt_at REAL NOT NULL DEFAULT 0,
                    lease_id TEXT,
                    lease_expires_at REAL,
                    created_at REAL NOT NULL,
                    UNIQUE(installation_id, summary_date)
                )
                """
            )
            try database.execute(
                """
                CREATE INDEX IF NOT EXISTS usage_outbox_ready
                ON usage_outbox(next_attempt_at, lease_id, summary_date)
                """
            )
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS usage_quarantine (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    summary_date TEXT NOT NULL,
                    attempt_count INTEGER NOT NULL,
                    status_code INTEGER NOT NULL,
                    quarantined_at REAL NOT NULL
                )
                """
            )
            try database.execute("PRAGMA user_version = 1")
        }
    }

    private func applyFileProtection(to databaseURL: URL) {
        #if os(iOS)
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ] where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
        #endif
    }

    private static var directoryProtectionAttributes: [
        FileAttributeKey: Any
    ]? {
        #if os(iOS)
        return [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        #else
        return nil
        #endif
    }

    private func absorbDatabaseErrors(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            // Usage metrics must never alter keyboard or host-app control flow.
        }
    }

    private static let unavailableSnapshot = KeyboardUsageRepositoryDebugSnapshot(
        isAvailable: false,
        daily: [],
        pending: [],
        quarantined: []
    )
}
