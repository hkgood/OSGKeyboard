// HostAppURLRegistryTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class HostAppURLRegistryTests: XCTestCase {
    func testWeChatLookup() {
        let entry = HostAppURLRegistry.lookup(bundleId: "com.tencent.xin")
        XCTAssertEqual(entry?.returnURLString, "weixin://")
        XCTAssertEqual(entry?.displayNameKey, "hostApp.wechat")
    }

    /// App Store bundle ids; the earlier `com.tencent.wework` / `tv.danmaku.bili` never matched.
    func testCorrectedBundleIds() {
        XCTAssertEqual(HostAppURLRegistry.lookup(bundleId: "com.tencent.ww")?.returnURLString, "wxwork://")
        XCTAssertEqual(HostAppURLRegistry.lookup(bundleId: "tv.danmaku.bilianime")?.returnURLString, "bilibili://")
    }

    func testSystemAppLookup() {
        XCTAssertEqual(HostAppURLRegistry.lookup(bundleId: "com.apple.mobilenotes")?.returnURLString, "mobilenotes://")
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: "com.apple.mobilesafari"))
    }

    func testUnknownBundleReturnsNil() {
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: "com.example.unknown"))
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: nil))
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: ""))
    }

    func testEveryEntryHasParseableReturnURL() {
        for entry in HostAppURLRegistry.entries {
            XCTAssertNotNil(entry.returnURL?.scheme, entry.bundleId)
        }
    }

    func testOwnBundleIdsAreNeverReturnTargets() {
        XCTAssertTrue(HostAppURLRegistry.isOwnBundleId("com.osgkeyboard"))
        XCTAssertTrue(HostAppURLRegistry.isOwnBundleId("com.osgkeyboard.ios"))
        XCTAssertTrue(HostAppURLRegistry.isOwnBundleId("com.osgkeyboard.ios.keyboard"))
        XCTAssertFalse(HostAppURLRegistry.isOwnBundleId("com.osgkeyboardx.ios"))
        XCTAssertFalse(HostAppURLRegistry.isOwnBundleId("com.tencent.xin"))
    }

    func testEntriesHaveUniqueBundleIds() {
        let ids = HostAppURLRegistry.entries.map(\.bundleId)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryEntryHasLocalizedDisplayName() throws {
        let bundle = Bundle(identifier: "com.osgkeyboard.ios") ?? .main
        for language in ["en", "zh-Hans"] {
            let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"), language)
            let strings = try XCTUnwrap(
                NSDictionary(contentsOfFile: "\(path)/Localizable.strings") as? [String: String],
                language
            )
            for entry in HostAppURLRegistry.entries {
                XCTAssertNotNil(strings[entry.displayNameKey], "\(language): \(entry.displayNameKey)")
            }
        }
    }
}
