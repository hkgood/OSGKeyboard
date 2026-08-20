// AIAddressExtractionTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class AIAddressExtractionTests: XCTestCase {
    func testNONEAndEmptyProduceNoItems() {
        XCTAssertEqual(AIAddressExtraction.lines(from: "NONE"), [])
        XCTAssertEqual(AIAddressExtraction.lines(from: "没有地址"), [])
        XCTAssertEqual(AIAddressExtraction.lines(from: "no address"), [])
        XCTAssertEqual(AIAddressExtraction.lines(from: "  \n  "), [])
    }

    func testDestinationOnlyKeepsLeadingPipe() {
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "|三里屯太古里"),
            ["|三里屯太古里"]
        )
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "朝阳区酒仙桥路10号"),
            ["|朝阳区酒仙桥路10号"]
        )
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "|三里屯|"),
            ["|三里屯"]
        )
    }

    func testOriginAndDestination() {
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "北京南站|三里屯太古里"),
            ["北京南站|三里屯太古里"]
        )
    }

    func testFirstValidLineOnly() {
        let raw = """
        NONE
        北京南站|三里屯
        国贸|望京
        """
        XCTAssertEqual(AIAddressExtraction.lines(from: raw), ["北京南站|三里屯"])
    }

    func testSameOriginAndDestinationDropsOrigin() {
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "故宫|故宫"),
            ["|故宫"]
        )
    }

    func testRejectsURLDestinations() {
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "|https://maps.apple.com/?daddr=x"),
            []
        )
    }

    func testStripsBullet() {
        XCTAssertEqual(
            AIAddressExtraction.lines(from: "- |三里屯"),
            ["|三里屯"]
        )
    }

    func testWholeClipboardEchoIsRejected() {
        let source = String(repeating: "这是一段很长的会议纪要内容，包含许多句子。", count: 4)
        XCTAssertEqual(
            AIAddressExtraction.lines(from: source, sourceClipboard: source),
            []
        )
    }

    func testPromptIncludesPipeContractAndNONE() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.navigateID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("起点|终点"))
        XCTAssertTrue(prompt.contains("NONE"))
        XCTAssertTrue(prompt.contains("不要把整段原文当成一个地点"))
    }

    func testEnglishPromptIncludesNONE() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.navigateID,
            locale: "en",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("origin|destination"))
        XCTAssertTrue(prompt.contains("NONE"))
    }
}

final class AIMapNavigationTests: XCTestCase {
    private let destinationOnly = AIMapRoute(origin: nil, destination: "三里屯太古里")
    private let twoPoint = AIMapRoute(origin: "北京南站", destination: "三里屯太古里")

    func testPrefersAmapWhenIosamapOpens() {
        let url = AIMapNavigation.url(for: destinationOnly) { $0.scheme == "iosamap" }
        XCTAssertEqual(url.scheme, "iosamap")
        XCTAssertEqual(url.host, "path")
        let items = query(url)
        XCTAssertEqual(items["sourceApplication"], "OSGKeyboard")
        XCTAssertEqual(items["dname"], "三里屯太古里")
        XCTAssertEqual(items["sname"], "我的位置")
        XCTAssertEqual(items["t"], "0")
    }

    func testAmapUsesAmapuriWhenOnlyAmapuriOpens() {
        let url = AIMapNavigation.url(for: twoPoint) { $0.scheme == "amapuri" }
        XCTAssertEqual(url.scheme, "amapuri")
        XCTAssertEqual(url.host, "route")
        XCTAssertTrue(url.absoluteString.contains("://route/plan/?"))
        let items = query(url)
        XCTAssertEqual(items["sname"], "北京南站")
        XCTAssertEqual(items["dname"], "三里屯太古里")
    }

    func testFallsBackToBaiduWhenAmapMissing() {
        let url = AIMapNavigation.url(for: twoPoint) { $0.scheme == "baidumap" }
        XCTAssertEqual(url.scheme, "baidumap")
        XCTAssertEqual(url.host, "map")
        XCTAssertEqual(url.path, "/direction")
        let items = query(url)
        XCTAssertEqual(items["origin"], "name:北京南站")
        XCTAssertEqual(items["destination"], "name:三里屯太古里")
        XCTAssertEqual(items["mode"], "driving")
    }

    func testBaiduOmitsOriginWhenStartingFromHere() {
        let url = AIMapNavigation.url(for: destinationOnly) { $0.scheme == "baidumap" }
        let items = query(url)
        XCTAssertNil(items["origin"])
        XCTAssertEqual(items["destination"], "name:三里屯太古里")
    }

    func testFallsBackToAppleMaps() {
        let url = AIMapNavigation.url(for: twoPoint) { _ in false }
        XCTAssertEqual(url.scheme, "maps")
        XCTAssertTrue(url.absoluteString.hasPrefix("maps://"))
        let items = query(url)
        XCTAssertEqual(items["saddr"], "北京南站")
        XCTAssertEqual(items["daddr"], "三里屯太古里")
        XCTAssertEqual(items["dirflg"], "d")
    }

    func testAppleOmitsSaddrWhenStartingFromHere() {
        let url = AIMapNavigation.url(for: destinationOnly) { _ in false }
        let items = query(url)
        XCTAssertNil(items["saddr"])
        XCTAssertEqual(items["daddr"], "三里屯太古里")
    }

    func testShortcutInputEncodesFirstRoute() {
        let text = AIMapNavigation.shortcutInput(from: "北京南站|三里屯") { _ in false }
        XCTAssertEqual(text?.hasPrefix("maps:"), true)
        XCTAssertTrue(text?.contains("daddr") == true)
    }

    func testShortcutInputRejectsNONE() {
        XCTAssertNil(AIMapNavigation.shortcutInput(from: "NONE") { _ in false })
    }

    func testProviderOrder() {
        XCTAssertEqual(AIMapNavigation.provider { $0.scheme == "iosamap" }, .amap)
        XCTAssertEqual(AIMapNavigation.provider { $0.scheme == "baidumap" }, .baidu)
        XCTAssertEqual(AIMapNavigation.provider { _ in false }, .apple)
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
    }
}
