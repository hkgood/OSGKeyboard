// AnalyticsRepository.swift
// OSGKeyboard · Shared
//
// Cross-process SQLite queue. The actor is the in-process isolation boundary;
// WAL and BEGIN IMMEDIATE provide the corresponding cross-process boundary.

import CryptoKit
import Foundation
import SQLite3

public struct AnalyticsBootstrapContext: Sendable {
    public let surface: AnalyticsSurface
    public let environment: AnalyticsEnvironment

    public init(
        surface: AnalyticsSurface,
        environment: AnalyticsEnvironment
    ) {
        self.surface = surface
        self.environment = environment
    }
}

public enum AnalyticsAccountObservation: Sendable {
    case firstAccount
    case unchanged
    case switchedAccount
    case analyticsDisabled
    case unavailable
}

public struct AnalyticsPendingEventDiagnostic: Sendable {
    public let rowID: Int64
    public let eventType: AnalyticsEventType?
    public let attemptCount: Int
    public let nextAttemptAt: Date
    public let payloadSize: Int
}

public struct AnalyticsQuarantinedEventDiagnostic: Sendable {
    public let rowID: Int64
    public let eventType: AnalyticsEventType?
    public let attemptCount: Int
    public let reason: String
    public let payloadSize: Int
}

public struct AnalyticsRepositoryDebugSnapshot: Sendable {
    public let isAvailable: Bool
    public let enabled: Bool
    public let installationID: UUID?
    public let firstOpenRecorded: Bool
    public let pendingEvents: [AnalyticsPendingEventDiagnostic]
    public let quarantinedEvents: [AnalyticsQuarantinedEventDiagnostic]
}

struct AnalyticsEventDimensions: Sendable {
    var acquisitionChannel: AnalyticsAcquisitionChannel?
    var feature: AnalyticsFeature?
    var executionMode: AnalyticsExecutionMode?
    var failureCategory: AnalyticsFailureCategory?
    var durationBucket: AnalyticsDurationBucket?

    static let none = Self()
}

struct AnalyticsLeasedEvent: Sendable {
    let rowID: Int64
    let payload: Data
    let attemptCount: Int
}

struct AnalyticsLeasedBatch: Sendable {
    let leaseID: String
    let events: [AnalyticsLeasedEvent]
    let body: Data
}

public actor AnalyticsRepository {
    private enum MetadataKey {
        static let enabled = "enabled"
        static let installationID = "installationId"
        static let firstOpenRecorded = "firstOpenRecorded"
        static let accountFingerprint = "accountFingerprint"
        static let uploadLeaseOwner = "uploadLeaseOwner"
        static let uploadLeaseExpiresAt = "uploadLeaseExpiresAt"
        static let expiredDropCount = "diagnostic.expiredDropCount"
        static let capacityDropCount = "diagnostic.capacityDropCount"

        static func lastSession(_ surface: AnalyticsSurface) -> String {
            "lastSession.\(surface.rawValue)"
        }
    }

    private let configuration: AnalyticsRepositoryConfiguration
    private let clock: any AnalyticsWallClock
    private let uuidGenerator: any AnalyticsUUIDGenerating
    private var database: SQLiteDatabase?
    private var isDatabaseAccessSuspended = false

    public init(
        configuration: AnalyticsRepositoryConfiguration = .appGroupDefault(),
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

    /// Runs after earlier actor operations, then closes the process-local
    /// connection. Later fire-and-forget records become best-effort no-ops
    /// until an explicitly authorized execution window resumes access.
    public func suspendDatabaseAccess() {
        isDatabaseAccessSuspended = true
        database = nil
    }

    /// The host calls this only after cold-start attribution has been resolved.
    /// Installation identity, FIRST_OPEN and its marker share one transaction.
    public func prepare(
        using context: AnalyticsBootstrapContext,
        firstOpenAcquisitionChannel: AnalyticsAcquisitionChannel
    ) {
        guard context.surface == .app else { return }
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                _ = try ensureEnabled(database)
                guard try isEnabled(database) else { return }
                let installationID = try ensureInstallation(database)
                guard try metadata(
                    for: MetadataKey.firstOpenRecorded,
                    database: database
                ) == nil else {
                    return
                }
                let event = try AnalyticsEvent(
                    installationId: installationID,
                    clientEventId: uuidGenerator.makeUUID(),
                    eventType: .firstOpen,
                    occurredAt: clock.now(),
                    surface: .app,
                    appVersion: context.environment.appVersion,
                    osVersion: context.environment.osVersion,
                    acquisitionChannel: firstOpenAcquisitionChannel
                )
                try insert(event, database: database)
                try setMetadata(
                    "1",
                    for: MetadataKey.firstOpenRecorded,
                    database: database
                )
                try enforceStoragePolicy(database)
            }
        }
    }

    public func isEnabled() -> Bool {
        guard let database = openDatabaseIfNeeded() else { return true }
        do {
            return try database.immediateTransaction {
                try ensureEnabled(database)
            }
        } catch {
            return true
        }
    }

    /// Read-only diagnostics for tests and support tooling. Event payload content
    /// is deliberately excluded from this public snapshot.
    public func debugSnapshot() -> AnalyticsRepositoryDebugSnapshot {
        guard let database = openDatabaseIfNeeded() else {
            return Self.unavailableDebugSnapshot
        }
        do {
            return try database.immediateTransaction {
                let enabled = try ensureEnabled(database)
                let installationID = try metadata(
                    for: MetadataKey.installationID,
                    database: database
                ).flatMap(UUID.init(uuidString:))
                let firstOpenRecorded = try metadata(
                    for: MetadataKey.firstOpenRecorded,
                    database: database
                ) == "1"
                let pending = try database.query(
                    """
                    SELECT id, event_type, attempt_count, next_attempt_at, payload_size
                    FROM pending_events
                    ORDER BY id ASC
                    """
                ).compactMap { row -> AnalyticsPendingEventDiagnostic? in
                    guard let rowID = row.int64(at: 0),
                          let eventTypeText = row.text(at: 1),
                          let attemptCount = row.int64(at: 2),
                          let nextAttemptAt = row.double(at: 3),
                          let payloadSize = row.int64(at: 4) else {
                        return nil
                    }
                    return AnalyticsPendingEventDiagnostic(
                        rowID: rowID,
                        eventType: AnalyticsEventType(rawValue: eventTypeText),
                        attemptCount: Int(attemptCount),
                        nextAttemptAt: Date(timeIntervalSince1970: nextAttemptAt),
                        payloadSize: Int(payloadSize)
                    )
                }
                let quarantined = try database.query(
                    """
                    SELECT id, event_type, attempt_count, reason, payload_size
                    FROM quarantined_events
                    ORDER BY id ASC
                    """
                ).compactMap { row -> AnalyticsQuarantinedEventDiagnostic? in
                    guard let rowID = row.int64(at: 0),
                          let eventTypeText = row.text(at: 1),
                          let attemptCount = row.int64(at: 2),
                          let reason = row.text(at: 3),
                          let payloadSize = row.int64(at: 4) else {
                        return nil
                    }
                    return AnalyticsQuarantinedEventDiagnostic(
                        rowID: rowID,
                        eventType: AnalyticsEventType(rawValue: eventTypeText),
                        attemptCount: Int(attemptCount),
                        reason: reason,
                        payloadSize: Int(payloadSize)
                    )
                }
                return AnalyticsRepositoryDebugSnapshot(
                    isAvailable: true,
                    enabled: enabled,
                    installationID: installationID,
                    firstOpenRecorded: firstOpenRecorded,
                    pendingEvents: pending,
                    quarantinedEvents: quarantined
                )
            }
        } catch {
            return Self.unavailableDebugSnapshot
        }
    }

    /// Internal raw-byte access is intentionally limited to @testable imports.
    func debugPayloadBytes(rowID: Int64, quarantined: Bool = false) -> Data? {
        guard let database = openDatabaseIfNeeded() else { return nil }
        let table = quarantined ? "quarantined_events" : "pending_events"
        do {
            return try database.query(
                "SELECT payload FROM \(table) WHERE id = ?",
                bindings: [.int64(rowID)]
            ).first?.data(at: 0)
        } catch {
            return nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                let wasEnabled = try ensureEnabled(database)
                guard wasEnabled != enabled else {
                    if enabled {
                        _ = try ensureInstallation(database)
                    }
                    return
                }

                if enabled {
                    try setMetadata("1", for: MetadataKey.enabled, database: database)
                    try rotateInstallation(database)
                } else {
                    try setMetadata("0", for: MetadataKey.enabled, database: database)
                    try clearQueues(database)
                    try clearUploadLease(database)
                }
            }
        }
    }

    public func observeAccount(
        stableIdentifier: String
    ) -> AnalyticsAccountObservation {
        guard let database = openDatabaseIfNeeded() else { return .unavailable }
        do {
            return try database.immediateTransaction {
                _ = try ensureEnabled(database)
                guard try isEnabled(database) else { return .analyticsDisabled }
                _ = try ensureInstallation(database)

                let fingerprint = Self.accountFingerprint(stableIdentifier)
                guard let existing = try metadata(
                    for: MetadataKey.accountFingerprint,
                    database: database
                ) else {
                    try setMetadata(
                        fingerprint,
                        for: MetadataKey.accountFingerprint,
                        database: database
                    )
                    return .firstAccount
                }
                guard existing != fingerprint else { return .unchanged }

                try setMetadata(
                    fingerprint,
                    for: MetadataKey.accountFingerprint,
                    database: database
                )
                try rotateInstallation(database)
                return .switchedAccount
            }
        } catch {
            return .unavailable
        }
    }

    /// Account deletion creates a fresh anonymous analytics identity and removes
    /// queued events while preserving the once-per-install FIRST_OPEN marker.
    public func handleAccountDeletion() {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                _ = try ensureEnabled(database)
                try removeMetadata(
                    for: MetadataKey.accountFingerprint,
                    database: database
                )
                guard try isEnabled(database) else {
                    try clearQueues(database)
                    return
                }
                try rotateInstallation(database)
            }
        }
    }

    func record(
        eventType: AnalyticsEventType,
        context: AnalyticsBootstrapContext,
        surfaceOverride: AnalyticsSurface? = nil,
        dimensions: AnalyticsEventDimensions = .none
    ) {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                _ = try ensureEnabled(database)
                guard try isEnabled(database) else { return }
                let installationID = try ensureInstallation(database)
                let event = try AnalyticsEvent(
                    installationId: installationID,
                    clientEventId: uuidGenerator.makeUUID(),
                    eventType: eventType,
                    occurredAt: clock.now(),
                    surface: surfaceOverride ?? context.surface,
                    appVersion: context.environment.appVersion,
                    osVersion: context.environment.osVersion,
                    acquisitionChannel: dimensions.acquisitionChannel,
                    feature: dimensions.feature,
                    executionMode: dimensions.executionMode,
                    failureCategory: dimensions.failureCategory,
                    durationBucket: dimensions.durationBucket
                )
                try insert(event, database: database)
                try enforceStoragePolicy(database)
            }
        }
    }

    /// Starts at most one session per surface in each rolling 30-minute window.
    func recordSessionIfNeeded(
        context: AnalyticsBootstrapContext
    ) {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                _ = try ensureEnabled(database)
                guard try isEnabled(database) else { return }
                let now = clock.now()
                let key = MetadataKey.lastSession(context.surface)
                if let text = try metadata(for: key, database: database),
                   let previous = TimeInterval(text) {
                    let elapsed = now.timeIntervalSince1970 - previous
                    if elapsed >= 0, elapsed < 30 * 60 {
                        // Session windows are based on inactivity, so every
                        // presentation refreshes the last-active timestamp.
                        try setMetadata(
                            String(now.timeIntervalSince1970),
                            for: key,
                            database: database
                        )
                        return
                    }
                }

                let installationID = try ensureInstallation(database)
                let event = try AnalyticsEvent(
                    installationId: installationID,
                    clientEventId: uuidGenerator.makeUUID(),
                    eventType: .sessionStarted,
                    occurredAt: now,
                    surface: context.surface,
                    appVersion: context.environment.appVersion,
                    osVersion: context.environment.osVersion
                )
                try insert(event, database: database)
                try setMetadata(
                    String(now.timeIntervalSince1970),
                    for: key,
                    database: database
                )
                try enforceStoragePolicy(database)
            }
        }
    }

    func leaseBatch(
        ownerID: String,
        configuration upload: AnalyticsUploadConfiguration
    ) -> AnalyticsLeasedBatch? {
        guard let database = openDatabaseIfNeeded() else { return nil }
        do {
            return try database.immediateTransaction {
                let now = clock.now().timeIntervalSince1970
                guard try acquireGlobalLease(
                    ownerID: ownerID,
                    expiresAt: now + upload.globalLeaseDuration,
                    now: now,
                    database: database
                ) else {
                    return nil
                }

                try releaseExpiredEventLeases(now: now, database: database)
                try deleteExpiredEvents(now: now, database: database)

                let candidates = try database.query(
                    """
                    SELECT id, payload, attempt_count
                    FROM pending_events
                    WHERE next_attempt_at <= ? AND lease_id IS NULL
                    ORDER BY priority DESC, created_at ASC
                    LIMIT ?
                    """,
                    bindings: [.double(now), .int64(Int64(upload.maximumBatchCount))]
                )

                var selected: [AnalyticsLeasedEvent] = []
                var bodySize = Self.emptyRequestBody.count
                for row in candidates {
                    guard let rowID = row.int64(at: 0),
                          let payload = row.data(at: 1),
                          let attempts = row.int64(at: 2) else {
                        continue
                    }
                    let additional = payload.count + (selected.isEmpty ? 0 : 1)
                    guard bodySize + additional <= upload.maximumBodyBytes else {
                        if selected.isEmpty {
                            try quarantineRows(
                                [rowID],
                                reason: "oversized",
                                database: database
                            )
                        }
                        break
                    }
                    selected.append(
                        AnalyticsLeasedEvent(
                            rowID: rowID,
                            payload: payload,
                            attemptCount: Int(attempts)
                        )
                    )
                    bodySize += additional
                }

                guard !selected.isEmpty else {
                    try clearUploadLease(database)
                    return nil
                }

                let leaseID = uuidGenerator.makeUUID().uuidString.lowercased()
                let leaseExpiry = now + upload.eventLeaseDuration
                for event in selected {
                    try database.execute(
                        """
                        UPDATE pending_events
                        SET lease_id = ?, lease_expires_at = ?
                        WHERE id = ? AND lease_id IS NULL
                        """,
                        bindings: [
                            .text(leaseID),
                            .double(leaseExpiry),
                            .int64(event.rowID)
                        ]
                    )
                }
                return AnalyticsLeasedBatch(
                    leaseID: leaseID,
                    events: selected,
                    body: Self.requestBody(for: selected)
                )
            }
        } catch {
            return nil
        }
    }

    func complete(
        rowIDs: [Int64],
        leaseID: String
    ) -> Bool {
        guard let database = openDatabaseIfNeeded(), !rowIDs.isEmpty else { return false }
        do {
            return try database.immediateTransaction {
                var deleted = 0
                for rowID in rowIDs {
                    try database.execute(
                        "DELETE FROM pending_events WHERE id = ? AND lease_id = ?",
                        bindings: [.int64(rowID), .text(leaseID)]
                    )
                    deleted += Int(database.changes)
                }
                guard deleted == rowIDs.count else {
                    throw SQLiteStoreError(
                        code: SQLITE_CONSTRAINT,
                        category: .constraint,
                        operation: "complete leased events"
                    )
                }
                return true
            }
        } catch {
            return false
        }
    }

    func quarantine(
        rowIDs: [Int64],
        leaseID: String,
        reason: String
    ) {
        guard let database = openDatabaseIfNeeded(), !rowIDs.isEmpty else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                try quarantineRows(
                    rowIDs,
                    leaseID: leaseID,
                    reason: reason,
                    database: database
                )
            }
        }
    }

    func scheduleRetry(
        events: [AnalyticsLeasedEvent],
        leaseID: String,
        delay: TimeInterval
    ) {
        guard let database = openDatabaseIfNeeded(), !events.isEmpty else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                let nextAttempt = clock.now().addingTimeInterval(max(0, delay))
                    .timeIntervalSince1970
                for event in events {
                    try database.execute(
                        """
                        UPDATE pending_events
                        SET attempt_count = attempt_count + 1,
                            next_attempt_at = ?,
                            lease_id = NULL,
                            lease_expires_at = NULL
                        WHERE id = ? AND lease_id = ?
                        """,
                        bindings: [
                            .double(nextAttempt),
                            .int64(event.rowID),
                            .text(leaseID)
                        ]
                    )
                }
            }
        }
    }

    func releaseGlobalLease(ownerID: String) {
        guard let database = openDatabaseIfNeeded() else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                try releaseGlobalLease(ownerID: ownerID, database: database)
            }
        }
    }

    func renewUploadLease(
        ownerID: String,
        leaseID: String,
        globalLeaseDuration: TimeInterval,
        eventLeaseDuration: TimeInterval
    ) -> Bool {
        guard let database = openDatabaseIfNeeded() else { return false }
        do {
            return try database.immediateTransaction {
                guard try metadata(
                    for: MetadataKey.uploadLeaseOwner,
                    database: database
                ) == ownerID else {
                    return false
                }
                let now = clock.now().timeIntervalSince1970
                try setMetadata(
                    String(now + globalLeaseDuration),
                    for: MetadataKey.uploadLeaseExpiresAt,
                    database: database
                )
                try database.execute(
                    """
                    UPDATE pending_events
                    SET lease_expires_at = ?
                    WHERE lease_id = ?
                    """,
                    bindings: [
                        .double(now + eventLeaseDuration),
                        .text(leaseID)
                    ]
                )
                return true
            }
        } catch {
            return false
        }
    }

    func releaseEvents(
        _ events: [AnalyticsLeasedEvent],
        leaseID: String
    ) {
        guard let database = openDatabaseIfNeeded(), !events.isEmpty else { return }
        absorbDatabaseErrors {
            try database.immediateTransaction {
                for event in events {
                    try database.execute(
                        """
                        UPDATE pending_events
                        SET lease_id = NULL, lease_expires_at = NULL
                        WHERE id = ? AND lease_id = ?
                        """,
                        bindings: [.int64(event.rowID), .text(leaseID)]
                    )
                }
            }
        }
    }

    // MARK: - Identity and queue policy

    private func ensureInstallation(
        _ database: SQLiteDatabase
    ) throws -> UUID {
        if let value = try metadata(for: MetadataKey.installationID, database: database),
           let identifier = UUID(uuidString: value) {
            return identifier
        }

        let identifier = uuidGenerator.makeUUID()
        try setMetadata(
            identifier.uuidString.lowercased(),
            for: MetadataKey.installationID,
            database: database
        )
        return identifier
    }

    private func rotateInstallation(
        _ database: SQLiteDatabase
    ) throws {
        try clearQueues(database)
        try clearUploadLease(database)
        try removeMetadata(for: MetadataKey.installationID, database: database)
        for surface in AnalyticsSurface.allCases {
            try removeMetadata(
                for: MetadataKey.lastSession(surface),
                database: database
            )
        }
        _ = try ensureInstallation(database)
    }

    private func insert(
        _ event: AnalyticsEvent,
        database: SQLiteDatabase
    ) throws {
        let payload = try AnalyticsCanonicalJSON.encode(event)
        try database.execute(
            """
            INSERT OR IGNORE INTO pending_events (
                client_event_id, event_type, occurred_at, surface, payload,
                payload_size, priority, lease_id, lease_expires_at,
                attempt_count, next_attempt_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, 0, 0, ?)
            """,
            bindings: [
                .text(event.clientEventId.uuidString.lowercased()),
                .text(event.eventType.rawValue),
                .double(event.occurredAt.timeIntervalSince1970),
                .text(event.surface.rawValue),
                .blob(payload),
                .int64(Int64(payload.count)),
                .int64(Int64(Self.priority(for: event.eventType))),
                .double(clock.now().timeIntervalSince1970)
            ]
        )
    }

    private func enforceStoragePolicy(_ database: SQLiteDatabase) throws {
        try deleteExpiredEvents(
            now: clock.now().timeIntervalSince1970,
            database: database
        )
        while true {
            let row = try database.query(
                """
                SELECT
                    (SELECT COUNT(*) FROM pending_events)
                        + (SELECT COUNT(*) FROM quarantined_events),
                    (SELECT COALESCE(SUM(payload_size), 0) FROM pending_events)
                        + (SELECT COALESCE(SUM(payload_size), 0) FROM quarantined_events)
                """
            ).first
            let count = row?.int64(at: 0) ?? 0
            let bytes = row?.int64(at: 1) ?? 0
            guard count > Int64(configuration.maximumEventCount)
                    || bytes > Int64(configuration.maximumStoredBytes) else {
                return
            }

            // Quarantined poison events are the least valuable retained records.
            try database.execute(
                """
                DELETE FROM quarantined_events
                WHERE id = (
                    SELECT id FROM quarantined_events
                    ORDER BY quarantined_at ASC
                    LIMIT 1
                )
                """
            )
            if database.changes > 0 {
                try incrementDiagnostic(
                    MetadataKey.capacityDropCount,
                    by: Int64(database.changes),
                    database: database
                )
                continue
            }
            try database.execute(
                """
                DELETE FROM pending_events
                WHERE id = (
                    SELECT id FROM pending_events
                    WHERE lease_id IS NULL
                    ORDER BY priority ASC, created_at ASC
                    LIMIT 1
                )
                """
            )
            guard database.changes > 0 else { return }
            try incrementDiagnostic(
                MetadataKey.capacityDropCount,
                by: Int64(database.changes),
                database: database
            )
        }
    }

    private func deleteExpiredEvents(
        now: TimeInterval,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            "DELETE FROM pending_events WHERE occurred_at < ?",
            bindings: [.double(now - configuration.eventRetention)]
        )
        var deleted = Int64(database.changes)
        try database.execute(
            "DELETE FROM quarantined_events WHERE occurred_at < ?",
            bindings: [.double(now - configuration.eventRetention)]
        )
        deleted += Int64(database.changes)
        try incrementDiagnostic(
            MetadataKey.expiredDropCount,
            by: deleted,
            database: database
        )
    }

    private func clearQueues(_ database: SQLiteDatabase) throws {
        try database.execute("DELETE FROM pending_events")
        try database.execute("DELETE FROM quarantined_events")
    }

    // MARK: - Leases

    private func acquireGlobalLease(
        ownerID: String,
        expiresAt: TimeInterval,
        now: TimeInterval,
        database: SQLiteDatabase
    ) throws -> Bool {
        let existingOwner = try metadata(
            for: MetadataKey.uploadLeaseOwner,
            database: database
        )
        let existingExpiry = try metadata(
            for: MetadataKey.uploadLeaseExpiresAt,
            database: database
        ).flatMap(TimeInterval.init) ?? 0
        guard existingOwner == nil || existingOwner == ownerID || existingExpiry <= now else {
            return false
        }
        try setMetadata(ownerID, for: MetadataKey.uploadLeaseOwner, database: database)
        try setMetadata(
            String(expiresAt),
            for: MetadataKey.uploadLeaseExpiresAt,
            database: database
        )
        return true
    }

    private func releaseGlobalLease(
        ownerID: String,
        database: SQLiteDatabase
    ) throws {
        guard try metadata(
            for: MetadataKey.uploadLeaseOwner,
            database: database
        ) == ownerID else {
            return
        }
        try clearUploadLease(database)
    }

    private func clearUploadLease(_ database: SQLiteDatabase) throws {
        try removeMetadata(for: MetadataKey.uploadLeaseOwner, database: database)
        try removeMetadata(for: MetadataKey.uploadLeaseExpiresAt, database: database)
    }

    private func releaseExpiredEventLeases(
        now: TimeInterval,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            UPDATE pending_events
            SET lease_id = NULL, lease_expires_at = NULL
            WHERE lease_expires_at IS NOT NULL AND lease_expires_at <= ?
            """,
            bindings: [.double(now)]
        )
    }

    private func quarantineRows(
        _ rowIDs: [Int64],
        leaseID: String? = nil,
        reason: String,
        database: SQLiteDatabase
    ) throws {
        for rowID in rowIDs {
            var bindings: [SQLiteBinding] = [
                .text(reason),
                .double(clock.now().timeIntervalSince1970),
                .int64(rowID)
            ]
            var leaseClause = ""
            if let leaseID {
                leaseClause = " AND lease_id = ?"
                bindings.append(.text(leaseID))
            }
            try database.execute(
                """
                INSERT INTO quarantined_events (
                    client_event_id, event_type, occurred_at, surface, payload,
                    payload_size, attempt_count, reason, quarantined_at
                )
                SELECT client_event_id, event_type, occurred_at, surface, payload,
                       payload_size, attempt_count, ?, ?
                FROM pending_events
                WHERE id = ?\(leaseClause)
                """,
                bindings: bindings
            )
            try database.execute(
                "DELETE FROM pending_events WHERE id = ?\(leaseClause)",
                bindings: leaseID.map {
                    [.int64(rowID), .text($0)]
                } ?? [.int64(rowID)]
            )
        }
        try enforceStoragePolicy(database)
    }

    private static let emptyRequestBody = Data(#"{"events":[]}"#.utf8)

    private static func requestBody(for events: [AnalyticsLeasedEvent]) -> Data {
        var body = Data(#"{"events":["#.utf8)
        for index in events.indices {
            if index > 0 {
                body.append(UInt8(ascii: ","))
            }
            body.append(events[index].payload)
        }
        body.append(Data("]}".utf8))
        return body
    }

    private static func priority(for eventType: AnalyticsEventType) -> Int {
        switch eventType {
        case .firstOpen, .aiFeatureSucceeded, .aiFeatureFailed:
            return 2
        case .aiFeatureStarted,
             .purchaseViewed,
             .purchaseStarted,
             .purchaseCancelled,
             .referralShared,
             .inviteOpened:
            return 1
        case .sessionStarted, .keyboardActivated:
            return 0
        }
    }

    // MARK: - Metadata and setup

    private func openDatabaseIfNeeded() -> SQLiteDatabase? {
        guard !isDatabaseAccessSuspended else { return nil }
        if let database {
            return database
        }
        guard let url = configuration.databaseURL else { return nil }
        do {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: Self.directoryProtectionAttributes
            )
            let opened = try SQLiteDatabase(
                url: url,
                busyTimeoutMilliseconds: configuration.busyTimeoutMilliseconds
            )
            try migrate(opened)
            applyFileProtection(to: url)
            database = opened
            return opened
        } catch {
            return nil
        }
    }

    private func migrate(_ database: SQLiteDatabase) throws {
        let version = try database.scalarInt64("PRAGMA user_version") ?? 0
        guard version <= 1 else {
            throw SQLiteStoreError(
                code: SQLITE_MISMATCH,
                category: .schema,
                operation: "validate schema version"
            )
        }
        if version == 0 {
            try database.immediateTransaction {
                try database.execute(
                    """
                    CREATE TABLE IF NOT EXISTS metadata (
                        key TEXT PRIMARY KEY NOT NULL,
                        value BLOB NOT NULL
                    ) WITHOUT ROWID
                    """
                )
                try database.execute(
                    """
                    CREATE TABLE IF NOT EXISTS pending_events (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        client_event_id TEXT UNIQUE NOT NULL,
                        event_type TEXT NOT NULL,
                        occurred_at REAL NOT NULL,
                        surface TEXT NOT NULL,
                        payload BLOB NOT NULL,
                        payload_size INTEGER NOT NULL CHECK(payload_size >= 0),
                        priority INTEGER NOT NULL,
                        lease_id TEXT,
                        lease_expires_at REAL,
                        attempt_count INTEGER NOT NULL DEFAULT 0,
                        next_attempt_at REAL NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL
                    )
                    """
                )
                try database.execute(
                    """
                    CREATE INDEX IF NOT EXISTS pending_events_ready
                    ON pending_events(next_attempt_at, lease_id, priority, created_at)
                    """
                )
                try database.execute(
                    """
                    CREATE INDEX IF NOT EXISTS pending_events_expiry
                    ON pending_events(occurred_at)
                    """
                )
                try database.execute(
                    """
                    CREATE TABLE IF NOT EXISTS quarantined_events (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        client_event_id TEXT UNIQUE NOT NULL,
                        event_type TEXT NOT NULL,
                        occurred_at REAL NOT NULL,
                        surface TEXT NOT NULL,
                        payload BLOB NOT NULL,
                        payload_size INTEGER NOT NULL,
                        attempt_count INTEGER NOT NULL,
                        reason TEXT NOT NULL,
                        quarantined_at REAL NOT NULL
                    )
                    """
                )
                try database.execute("PRAGMA user_version = 1")
            }
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

    @discardableResult
    private func ensureEnabled(_ database: SQLiteDatabase) throws -> Bool {
        if let value = try metadata(for: MetadataKey.enabled, database: database) {
            return value == "1"
        }
        try setMetadata("1", for: MetadataKey.enabled, database: database)
        return true
    }

    private func isEnabled(_ database: SQLiteDatabase) throws -> Bool {
        try metadata(for: MetadataKey.enabled, database: database) != "0"
    }

    private func metadata(
        for key: String,
        database: SQLiteDatabase
    ) throws -> String? {
        try database.query(
            "SELECT value FROM metadata WHERE key = ?",
            bindings: [.text(key)]
        ).first?.text(at: 0)
    }

    private func setMetadata(
        _ value: String,
        for key: String,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO metadata(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            bindings: [.text(key), .text(value)]
        )
    }

    private func removeMetadata(
        for key: String,
        database: SQLiteDatabase
    ) throws {
        try database.execute(
            "DELETE FROM metadata WHERE key = ?",
            bindings: [.text(key)]
        )
    }

    private func incrementDiagnostic(
        _ key: String,
        by amount: Int64,
        database: SQLiteDatabase
    ) throws {
        guard amount > 0 else { return }
        let existing = try metadata(for: key, database: database).flatMap(Int64.init) ?? 0
        try setMetadata(String(existing + amount), for: key, database: database)
    }

    private func absorbDatabaseErrors(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            // Analytics must never alter the host app's business control flow.
        }
    }

    private static let unavailableDebugSnapshot = AnalyticsRepositoryDebugSnapshot(
        isAvailable: false,
        enabled: true,
        installationID: nil,
        firstOpenRecorded: false,
        pendingEvents: [],
        quarantinedEvents: []
    )

    private static func accountFingerprint(_ identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - SQLite C API boundary

private enum SQLiteErrorCategory: Sendable {
    case busy
    case constraint
    case corrupt
    case io
    case schema
    case other
}

private struct SQLiteStoreError: Error, Sendable {
    let code: Int32
    let category: SQLiteErrorCategory
    let operation: String
}

private enum SQLiteBinding {
    case null
    case int64(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

private struct SQLiteRow {
    private let values: [SQLiteValue]

    init(statement: OpaquePointer) {
        values = (0..<sqlite3_column_count(statement)).map { index in
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                return .int64(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                return .double(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                guard let pointer = sqlite3_column_text(statement, index) else {
                    return .null
                }
                return .text(String(cString: pointer))
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, index))
                guard count > 0, let pointer = sqlite3_column_blob(statement, index) else {
                    return .blob(Data())
                }
                return .blob(Data(bytes: pointer, count: count))
            default:
                return .null
            }
        }
    }

    func int64(at index: Int) -> Int64? {
        guard values.indices.contains(index), case .int64(let value) = values[index] else {
            return nil
        }
        return value
    }

    func text(at index: Int) -> String? {
        guard values.indices.contains(index) else { return nil }
        switch values[index] {
        case .text(let value):
            return value
        case .blob(let data):
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    func double(at index: Int) -> Double? {
        guard values.indices.contains(index) else { return nil }
        switch values[index] {
        case .double(let value):
            return value
        case .int64(let value):
            return Double(value)
        default:
            return nil
        }
    }

    func data(at index: Int) -> Data? {
        guard values.indices.contains(index), case .blob(let value) = values[index] else {
            return nil
        }
        return value
    }
}

private enum SQLiteValue {
    case null
    case int64(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

private final class SQLiteDatabase {
    private static let transient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private var handle: OpaquePointer?

    init(url: URL, busyTimeoutMilliseconds: Int32) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &opened, flags, nil)
        guard result == SQLITE_OK, let opened else {
            if let opened {
                sqlite3_close_v2(opened)
            }
            throw Self.error(code: result, operation: "open database")
        }
        handle = opened
        sqlite3_extended_result_codes(opened, 1)
        sqlite3_busy_timeout(opened, busyTimeoutMilliseconds)
        do {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA foreign_keys = ON")
        } catch {
            sqlite3_close_v2(opened)
            handle = nil
            throw error
        }
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    var changes: Int32 {
        guard let handle else { return 0 }
        return sqlite3_changes(handle)
    }

    func execute(
        _ sql: String,
        bindings: [SQLiteBinding] = []
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw currentError(operation: "execute statement")
        }
    }

    func query(
        _ sql: String,
        bindings: [SQLiteBinding] = []
    ) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [SQLiteRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append(SQLiteRow(statement: statement))
            case SQLITE_DONE:
                return rows
            default:
                throw currentError(operation: "query statement")
            }
        }
    }

    func scalarInt64(_ sql: String) throws -> Int64? {
        try query(sql).first?.int64(at: 0)
    }

    func immediateTransaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try operation()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else {
            throw Self.error(code: SQLITE_MISUSE, operation: "prepare closed database")
        }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw currentError(operation: "prepare statement")
        }
        return statement
    }

    private func bind(
        _ bindings: [SQLiteBinding],
        to statement: OpaquePointer
    ) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .int64(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(
                        statement,
                        index,
                        bytes.baseAddress,
                        Int32(bytes.count),
                        Self.transient
                    )
                }
            }
            guard result == SQLITE_OK else {
                throw currentError(operation: "bind statement")
            }
        }
    }

    private func currentError(operation: String) -> SQLiteStoreError {
        guard let handle else {
            return Self.error(code: SQLITE_MISUSE, operation: operation)
        }
        return Self.error(code: sqlite3_extended_errcode(handle), operation: operation)
    }

    private static func error(
        code: Int32,
        operation: String
    ) -> SQLiteStoreError {
        let primary = code & 0xFF
        let category: SQLiteErrorCategory
        switch primary {
        case SQLITE_BUSY, SQLITE_LOCKED:
            category = .busy
        case SQLITE_CONSTRAINT:
            category = .constraint
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            category = .corrupt
        case SQLITE_IOERR, SQLITE_CANTOPEN, SQLITE_FULL:
            category = .io
        case SQLITE_SCHEMA, SQLITE_MISMATCH:
            category = .schema
        default:
            category = .other
        }
        return SQLiteStoreError(code: code, category: category, operation: operation)
    }
}
