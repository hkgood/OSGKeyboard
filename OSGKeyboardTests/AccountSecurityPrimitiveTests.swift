// AccountSecurityPrimitiveTests.swift
// OSGKeyboardTests
//
// Fixed vectors for nonce hashing, canonical payloads, and Keychain isolation.

@testable import OSGKeyboardHostSupport
import XCTest

final class AccountSecurityPrimitiveTests: XCTestCase {
    func testNonceUsesRawBase64URLAndLowercaseSHA256Hex() throws {
        let bytes = Data(0..<32)
        let generator = AppleSignInNonceGenerator(
            random: FixedRandomBytesGenerator(value: bytes)
        )

        let nonce = try generator.makeNonce()

        XCTAssertEqual(
            nonce.rawValue,
            "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
        )
        XCTAssertEqual(
            nonce.sha256Hex,
            "ea866a757e4c38babfa8127cbe9a409d3e1f93a00ff1488ff735fcf917afffd0"
        )
        XCTAssertNotNil(
            nonce.sha256Hex.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            )
        )
    }

    func testAppleSignInCanonicalPayloadMatchesServerByteForByte() throws {
        let payload = try AppAttestCanonicalPayload.appleSignIn(
            challenge: "AQID",
            credential: AppleSignInCredential(
                identityToken: "identity-token",
                authorizationCode: "authorization-code"
            ),
            rawNonce: "raw-nonce"
        )

        XCTAssertEqual(
            String(data: payload, encoding: .utf8),
            """
            osg-app-attest-v1
            purpose=apple-sign-in
            challenge=AQID
            identity_token_sha256=OcwzHhEgHO3_IBV8hI8o_WTuAx0hgRrERJAbfcPbjvA
            authorization_code_sha256=WVYUJ4163Fe7kuKPogOooY15egdoT9_3XLvyqW6_hXc
            nonce_sha256=LF0QeTgFOiJ18CLBU8mnH2XuB3VLi8pUPul6DDzGaZA

            """
        )
        XCTAssertEqual(payload.last, 0x0A, "The server contract includes the final line feed")
    }

    func testOOBEGrantCanonicalPayloadMatchesServerByteForByte() throws {
        let installationID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!

        let payload = try AppAttestCanonicalPayload.oobeGrant(
            challenge: "AQID",
            installationID: installationID,
            keyID: "app-attest-key"
        )

        XCTAssertEqual(
            String(data: payload, encoding: .utf8),
            """
            osg-app-attest-v1
            purpose=oobe-gateway-grant
            challenge=AQID
            key_id=app-attest-key
            installation_id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
            scopes=ai,polish
            features=ask_ai,clipboard_reply,clipboard_translate,voice_input
            grant_ttl_seconds=1800
            access_ttl_seconds=300

            """
        )
        XCTAssertEqual(payload.last, 0x0A)
    }

    func testHostPrivateKeychainDescriptorRejectsSharedAccessGroup() throws {
        XCTAssertThrowsError(
            try HostPrivateAccountKeychainDescriptor(
                accessGroup: "TEAMID.com.osgkeyboard.shared"
            )
        )

        let descriptor = try HostPrivateAccountKeychainDescriptor.hostApplication(
            appIdentifierPrefix: "TEAMID"
        )
        XCTAssertEqual(descriptor.service, "com.osgkeyboard.ios.account")
        XCTAssertEqual(descriptor.accessGroup, "TEAMID.com.osgkeyboard.ios")
    }

    func testBase64URLRejectsNonCanonicalAlphabet() {
        XCTAssertNil(Data(base64URLEncoded: "AQID="))
        XCTAssertNil(Data(base64URLEncoded: "AQ+ID"))
        XCTAssertEqual(Data(base64URLEncoded: "AQID"), Data([1, 2, 3]))
    }
}
