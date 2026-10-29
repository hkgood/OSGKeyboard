// DebugAccountSessionHandoff.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Moves a signed-in account session from a physical device to the Simulator,
// which cannot produce DeviceCheck / App Attest evidence and so cannot sign in
// itself. Flow:
//
//   1. Device: Settings → Diagnostics → hand off. The session is removed from
//      the device (no server logout) and written to a file for AirDrop.
//   2. Mac:    Scripts/sim-import-account-session.sh <file> [udid]
//   3. Sim:    on launch the app adopts the file, deletes it, and restores the
//      session normally.
//
// On the Simulator the same file parks the session, so the signed-out state
// can be tested without a server logout ending the session.
//
// The file holds a live refresh token — treat it like a password.

#if DEBUG
import Foundation
#if canImport(OSGKeyboardHostSupport)
import OSGKeyboardHostSupport
#endif

/// Implemented by the live account service; UI-test and unavailable services
/// deliberately do not conform.
protocol DebugAccountSessionHandingOff: Sendable {
    /// Revokes this device's gateway grant, then returns the session after
    /// removing it locally. The server-side session stays valid.
    func debugRelinquishSession() async throws -> AccountTokenSession
    func debugAdoptSession(_ session: AccountTokenSession) async throws
}

enum DebugAccountSessionHandoff {
    static let fileName = "osg-account-handoff.json"
    static let format = "osg-debug-account-handoff-v1"
    private static let importedAccountKey = "debug.accountHandoff.importedAccountID"

    private struct Envelope: Codable {
        let format: String
        let session: AccountTokenSession
    }

    enum HandoffError: Error, Equatable {
        case unsupportedService
    }

    static func encode(_ session: AccountTokenSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(format: format, session: session))
    }

    static func decode(_ data: Data) -> AccountTokenSession? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.format == format else {
            return nil
        }
        return envelope.session
    }

    /// Device side: the file for the share sheet.
    static func writeExportFile(
        _ session: AccountTokenSession,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        try encode(session).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Simulator side: reads and always deletes the file the import script
    /// placed in Documents, so a malformed file cannot linger either.
    static func consumePendingImport(
        directory: URL = defaultImportDirectory
    ) -> AccountTokenSession? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return decode(data)
    }

    static func hasPendingImport(directory: URL = defaultImportDirectory) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
    }

    static var defaultImportDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// An imported session has no Apple credential for this Simulator's Apple
    /// ID, so the foreground credential check would sign it out immediately.
    static func markImported(accountID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(accountID.uuidString, forKey: importedAccountKey)
    }

    static func isImported(accountID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: importedAccountKey) == accountID.uuidString
    }
}
#endif
