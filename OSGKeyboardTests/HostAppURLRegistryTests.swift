// HostAppURLRegistryTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class HostAppURLRegistryTests: XCTestCase {
    func testWeChatLookup() {
        let entry = HostAppURLRegistry.lookup(bundleId: "com.tencent.xin")
        XCTAssertEqual(entry?.returnURLString, "weixin://")
        XCTAssertEqual(entry?.displayNameKey, "hostApp.wechat")
    }

    func testUnknownBundleReturnsNil() {
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: "com.apple.MobileSMS"))
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: nil))
        XCTAssertNil(HostAppURLRegistry.lookup(bundleId: ""))
    }

    func testQuerySchemesIncludesWeChat() {
        XCTAssertTrue(HostAppURLRegistry.querySchemes.contains("weixin"))
    }

    func testEntriesHaveUniqueBundleIds() {
        let ids = HostAppURLRegistry.entries.map(\.bundleId)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
