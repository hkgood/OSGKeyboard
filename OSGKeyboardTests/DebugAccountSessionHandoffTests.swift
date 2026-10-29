// DebugAccountSessionHandoffTests.swift
// OSGKeyboardTests
//
// DEBUG-only device → Simulator session handoff: the device must forget the
// session it hands off, and the Simulator must never keep the handoff file.

#if DEBUG
@testable import OSGKeyboard
@testable import OSGKeyboardHostSupport
import XCTest

final class DebugAccountSessionHandoffTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - AccountAPIClient

    func testRelinquishReturnsSessionAndForgetsItEverywhere() async throws {
        let session = makeAccountSession()
        let store = InMemoryAccountSecurityStore(session: session)
        let client = makeClient(store: store)
        // Warm the in-memory cache: clearing Keychain alone would not stop it.
        _ = try await client.currentSession()

        let relinquished = try await client.debugRelinquishSession()

        XCTAssertEqual(relinquished, session)
        let stored = await store.session
        XCTAssertNil(stored)
        let current = try await client.currentSession()
        XCTAssertNil(current)
    }

    func testRelinquishWithoutSessionThrows() async {
        let client = makeClient(store: InMemoryAccountSecurityStore())

        do {
            _ = try await client.debugRelinquishSession()
            XCTFail("Expected sessionUnavailable")
        } catch {
            XCTAssertEqual(error as? AccountAPIError, .sessionUnavailable)
        }
    }

    func testAdoptReplacesCachedSession() async throws {
        let store = InMemoryAccountSecurityStore(session: makeAccountSession())
        let client = makeClient(store: store)
        _ = try await client.currentSession()
        let handedOff = makeAccountSession(accessToken: "access-device", refreshToken: "refresh-device")

        try await client.debugAdoptSession(handedOff)

        let current = try await client.currentSession()
        XCTAssertEqual(current, handedOff)
        let stored = await store.session
        XCTAssertEqual(stored, handedOff)
    }

    // MARK: - Handoff file

    func testExportFileRoundTripsThroughImportAndIsDeleted() throws {
        let session = makeAccountSession()
        let url = try DebugAccountSessionHandoff.writeExportFile(session, directory: directory)

        let imported = DebugAccountSessionHandoff.consumePendingImport(directory: directory)

        XCTAssertEqual(imported, session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMalformedImportIsRejectedAndStillDeleted() throws {
        let url = directory.appendingPathComponent(DebugAccountSessionHandoff.fileName)
        try Data(#"{"format":"something-else","session":{}}"#.utf8).write(to: url)

        XCTAssertNil(DebugAccountSessionHandoff.consumePendingImport(directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testParkedSessionIsPendingUntilConsumed() throws {
        XCTAssertFalse(DebugAccountSessionHandoff.hasPendingImport(directory: directory))
        _ = try DebugAccountSessionHandoff.writeExportFile(makeAccountSession(), directory: directory)

        XCTAssertTrue(DebugAccountSessionHandoff.hasPendingImport(directory: directory))
        _ = DebugAccountSessionHandoff.consumePendingImport(directory: directory)
        XCTAssertFalse(DebugAccountSessionHandoff.hasPendingImport(directory: directory))
    }

    func testMissingImportReturnsNil() {
        XCTAssertNil(DebugAccountSessionHandoff.consumePendingImport(directory: directory))
    }

    func testImportedMarkerMatchesOnlyTheImportedAccount() throws {
        let suite = "DebugAccountSessionHandoffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let imported = makeAccountSession().accountId

        DebugAccountSessionHandoff.markImported(accountID: imported, defaults: defaults)

        XCTAssertTrue(DebugAccountSessionHandoff.isImported(accountID: imported, defaults: defaults))
        XCTAssertFalse(DebugAccountSessionHandoff.isImported(accountID: UUID(), defaults: defaults))
    }

    private func makeClient(store: InMemoryAccountSecurityStore) -> AccountAPIClient {
        AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: QueueAccountTransport([]),
            sessionVault: store
        )
    }
}
#endif
