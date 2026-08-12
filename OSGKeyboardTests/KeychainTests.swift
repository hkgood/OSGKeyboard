// KeychainTests.swift
// OSGKeyboard · Tests
//
// Unit tests for the Keychain helper and the one-time migration from
// the legacy UserDefaults slot. The Keychain is process-global in the
// simulator, so every test cleans up after itself.

import XCTest
@testable import OSGKeyboardShared

final class KeychainTests: XCTestCase {

    override func setUpWithError() throws {
        Keychain.resetTestMemoryStore()
        try? Keychain.deleteAPIKey()
        try? Keychain.deleteLegacyAPIKey()
        try? Keychain.deleteAPIKey(for: "qwen")
        try? Keychain.deleteAPIKey(for: "openai")
        try? Keychain.deleteAPIKey(for: "deepseek")
        try? Keychain.deleteAPIKey(for: "qwen", useICloudSync: true)
        try? Keychain.deleteAPIKey(for: "openai", useICloudSync: true)
        try? Keychain.deleteAPIKey(for: "deepseek", useICloudSync: true)
        try? Keychain.deleteASRAPIKey(for: "openai", useICloudSync: true)
    }

    override func tearDownWithError() throws {
        try? Keychain.deleteAPIKey()
        try? Keychain.deleteLegacyAPIKey()
        try? Keychain.deleteAPIKey(for: "qwen")
        try? Keychain.deleteAPIKey(for: "openai")
        try? Keychain.deleteAPIKey(for: "deepseek")
        try? Keychain.deleteAPIKey(for: "qwen", useICloudSync: true)
        try? Keychain.deleteAPIKey(for: "openai", useICloudSync: true)
        try? Keychain.deleteAPIKey(for: "deepseek", useICloudSync: true)
        try? Keychain.deleteASRAPIKey(for: "openai", useICloudSync: true)
        Keychain.resetTestMemoryStore()
    }

    // MARK: - Round-trip

    func testRoundTripWriteReadDelete() throws {
        // Nothing stored yet.
        XCTAssertNil(Keychain.apiKey(), "Keychain should start empty after cleanup")

        // Write → read.
        try Keychain.setAPIKey("sk-roundtrip-1")
        XCTAssertEqual(Keychain.apiKey(), "sk-roundtrip-1")

        // Overwrite → read new value (no orphan entries).
        try Keychain.setAPIKey("sk-roundtrip-2")
        XCTAssertEqual(Keychain.apiKey(), "sk-roundtrip-2")

        // Delete → read nil.
        try Keychain.deleteAPIKey()
        XCTAssertNil(Keychain.apiKey())
    }

    /// Empty string must DELETE the entry, not store an empty placeholder.
    /// Otherwise `Keychain.apiKey() ?? ""` would always return "" for any
    /// missing item, and the LLM client couldn't tell "stored but empty"
    /// (user error) from "not stored" (onboarding state).
    func testEmptyStringDeletes() throws {
        try Keychain.setAPIKey("sk-temp")
        XCTAssertEqual(Keychain.apiKey(), "sk-temp")

        try Keychain.setAPIKey("")
        XCTAssertNil(Keychain.apiKey(), "Empty write must delete, not store empty string")
    }

    func testProviderScopedKeysDoNotMix() throws {
        try Keychain.setAPIKey("sk-openai", for: "openai")
        try Keychain.setAPIKey("sk-qwen", for: "qwen")
        XCTAssertEqual(Keychain.apiKey(for: "openai"), "sk-openai")
        XCTAssertEqual(Keychain.apiKey(for: "qwen"), "sk-qwen")
    }

    func testSynchronizedWritesVerifyBeforeRemovingLocalCopies() throws {
        try Keychain.setAPIKey("llm-local", for: "openai")
        try Keychain.setASRAPIKey("asr-local", for: "openai")

        try Keychain.setAPIKey("llm-synced", for: "openai", useICloudSync: true)
        try Keychain.setASRAPIKey("asr-synced", for: "openai", useICloudSync: true)

        XCTAssertEqual(Keychain.apiKey(for: "openai", preferICloudSync: false), "llm-synced")
        XCTAssertEqual(Keychain.asrApiKey(for: "openai", preferICloudSync: false), "asr-synced")
        XCTAssertEqual(Keychain.apiKey(for: "openai", preferICloudSync: true), "llm-synced")
        XCTAssertEqual(Keychain.asrApiKey(for: "openai", preferICloudSync: true), "asr-synced")
    }

    /// Deleting a non-existent entry must be a no-op (idempotent), not an
    /// error — callers like `ProviderConfig.reset()` invoke it
    /// unconditionally.
    func testDeleteIsIdempotent() throws {
        // No prior write — should not throw.
        XCTAssertNoThrow(try Keychain.deleteAPIKey())
        XCTAssertNoThrow(try Keychain.deleteAPIKey())
    }

    // MARK: - Safe credential migration

    func testMirroredWriteFailureRestoresBothPreviousValues() {
        enum TestFailure: Error { case unavailable }
        var local: String? = "old-local"
        var synchronizable: String? = "old-sync"

        XCTAssertThrowsError(
            try Keychain.writeMirroredCredential(
                "new-value",
                readLocal: { local },
                readSynchronizable: { synchronizable },
                writeLocal: { local = $0 },
                writeSynchronizable: {
                    synchronizable = $0
                    throw TestFailure.unavailable
                },
                deleteLocal: { local = nil },
                deleteSynchronizable: { synchronizable = nil }
            )
        ) { error in
            XCTAssertEqual(error as? Keychain.CredentialMigrationError, .unavailable)
        }
        XCTAssertEqual(local, "old-local")
        XCTAssertEqual(synchronizable, "old-sync")
    }

    func testCopyTransactionWriteFailureKeepsSource() {
        enum TestFailure: Error { case unavailable }
        var source: String? = "credential"
        var destination: String?

        XCTAssertThrowsError(
            try Keychain.copyCredentialTransaction(
                source: { source },
                destination: { destination },
                writeDestination: { _ in throw TestFailure.unavailable },
                readbackDestination: { destination },
                deleteSource: { source = nil }
            )
        ) { error in
            XCTAssertEqual(error as? Keychain.CredentialMigrationError, .unavailable)
        }
        XCTAssertNotNil(source)
        XCTAssertNil(destination)
    }

    func testCopyTransactionRejectsDifferentDestinationWithoutDeletingSource() {
        var source: String? = "source-credential"
        var destination: String? = "destination-credential"
        var didWrite = false

        XCTAssertThrowsError(
            try Keychain.copyCredentialTransaction(
                source: { source },
                destination: { destination },
                writeDestination: { value in
                    didWrite = true
                    destination = value
                },
                readbackDestination: { destination },
                deleteSource: { source = nil }
            )
        ) { error in
            XCTAssertEqual(error as? Keychain.CredentialMigrationError, .conflict)
        }
        XCTAssertFalse(didWrite)
        XCTAssertNotNil(source)
        XCTAssertNotNil(destination)
    }

    func testCopyTransactionVerificationFailureKeepsSource() {
        var source: String? = "credential"
        var destination: String?

        XCTAssertThrowsError(
            try Keychain.copyCredentialTransaction(
                source: { source },
                destination: { destination },
                writeDestination: { destination = $0 },
                readbackDestination: { "different-readback" },
                deleteSource: { source = nil }
            )
        ) { error in
            XCTAssertEqual(error as? Keychain.CredentialMigrationError, .verificationFailed)
        }
        XCTAssertNotNil(source)
    }

    func testCopyTransactionDeletesSourceOnlyAfterVerifiedReadback() throws {
        var source: String? = "credential"
        var destination: String?

        try Keychain.copyCredentialTransaction(
            source: { source },
            destination: { destination },
            writeDestination: { destination = $0 },
            readbackDestination: { destination },
            deleteSource: { source = nil }
        )

        XCTAssertNil(source)
        XCTAssertNotNil(destination)
    }

    func testLocalToICloudMigrationCoversLLMAndASRKeys() throws {
        try Keychain.setAPIKey("llm-credential", for: "openai", useICloudSync: false)
        try Keychain.setASRAPIKey("asr-credential", for: "openai", useICloudSync: false)

        try Keychain.migrateLocalKeysToICloud()

        XCTAssertEqual(Keychain.apiKey(for: "openai", preferICloudSync: false), "llm-credential")
        XCTAssertEqual(Keychain.asrApiKey(for: "openai", preferICloudSync: false), "asr-credential")
        XCTAssertNotNil(Keychain.apiKey(for: "openai", preferICloudSync: true))
        XCTAssertNotNil(Keychain.asrApiKey(for: "openai", preferICloudSync: true))
    }

    // MARK: - AppGroupStore reading

    /// `AppGroupStore.apiKey` must consult the Keychain (not UserDefaults),
    /// otherwise the keyboard extension never sees the key set in the
    /// host app's Settings UI.
    func testAppGroupStoreReadsFromKeychain() throws {
        let suiteName = "group.com.osgkeyboard.shared.tests.kc.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try Keychain.setAPIKey("sk-from-store")
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.apiKey, "sk-from-store")
    }

    // MARK: - Legacy migration

    /// Pre-Keychain versions of the app stored the API key in
    /// `config.apiKey` (UserDefaults). On first init after upgrade, that
    /// value must be moved to the Keychain and removed from UserDefaults
    /// — otherwise a fresh install in a clean simulator would inherit the
    /// stale plaintext value.
    func testLegacyUserDefaultsKeyIsMigratedToKeychain() {
        let suiteName = "group.com.osgkeyboard.shared.tests.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Pre-upgrade state: apiKey lives in UserDefaults.
        defaults.set("sk-legacy-plaintext", forKey: "config.apiKey")

        // First init after upgrade: triggers the one-shot migration.
        let config = ProviderConfig(defaults: defaults)

        XCTAssertEqual(config.apiKey, "sk-legacy-plaintext",
                       "Migrated key must surface through ProviderConfig")
        // Migration follows `settingsICloudSyncEnabled` (default on) into the
        // synchronizable Keychain slot — read with the same preference.
        XCTAssertEqual(
            Keychain.apiKey(
                for: AppGroupConfiguration.defaultPolishProviderId,
                preferICloudSync: true
            ),
            "sk-legacy-plaintext",
            "Legacy value must land in Keychain after migration"
        )
        XCTAssertNil(defaults.string(forKey: "config.apiKey"),
                     "Legacy UserDefaults entry must be cleared after migration")

        // Second init (no legacy value left) reads from Keychain only.
        let config2 = ProviderConfig(defaults: defaults)
        XCTAssertEqual(config2.apiKey, "sk-legacy-plaintext")
    }

    /// If both the Keychain and the legacy UserDefaults slot have a value
    /// — possible on a downgrade or a torn update — Keychain wins. We
    /// don't delete the UserDefaults value, but the running app reads from
    /// the Keychain only.
    func testKeychainWinsOverLegacyWhenBothPresent() {
        let suiteName = "group.com.osgkeyboard.shared.tests.migration2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Set both.
        try? Keychain.setAPIKey("sk-new")
        defaults.set("sk-old", forKey: "config.apiKey")

        let config = ProviderConfig(defaults: defaults)
        XCTAssertEqual(config.apiKey, "sk-new", "Keychain value must take precedence")
        // Migration only fires when Keychain was nil — we did NOT delete
        // the legacy entry here. That's fine because Keychain is the
        // source of truth from now on; the legacy value is dead weight
        // but not incorrect.
    }
}
