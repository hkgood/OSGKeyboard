// LibrimeIntegrationTests.swift
// OSGKeyboard · Ext unit tests

import XCTest
@testable import OSGKeyboardShared

final class LibrimeIntegrationTests: XCTestCase {
    func testFullPinyinAndBothDoublePinyinSchemasProducePhraseCandidates() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OSGRimeTests-\(UUID().uuidString)", isDirectory: true)
        let shared = root.appendingPathComponent("SharedSupport", isDirectory: true)
        let user = root.appendingPathComponent("UserData", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: user, withIntermediateDirectories: true)

        let bundle = Bundle(for: LibrimeIntegrationTests.self)
        let dictionary = try XCTUnwrap(
            bundle.url(forResource: "osg_pinyin.dict", withExtension: "yaml")
        )
        try fileManager.copyItem(
            at: dictionary,
            to: shared.appendingPathComponent("osg_pinyin.dict.yaml")
        )
        try RimeSchemaGenerator.defaultConfiguration().write(
            to: shared.appendingPathComponent("default.yaml"),
            atomically: true,
            encoding: .utf8
        )
        for schema in TypingInputSchema.allCases {
            try RimeSchemaGenerator.schema(for: schema, fuzzyPairs: []).write(
                to: shared.appendingPathComponent("\(schema.rawValue).schema.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }

        let deployer = OSGRimeBridge(
            sharedDataDirectory: shared.path,
            userDataDirectory: user.path,
            distributionVersion: "tests"
        )
        try deployer.deploy(withFullCheck: true)
        deployer.finalizeRuntime()

        let bridge = OSGRimeBridge(
            sharedDataDirectory: shared.path,
            userDataDirectory: user.path,
            distributionVersion: "tests"
        )
        try bridge.start()

        let vectors: [(TypingInputSchema, String)] = [
            (.fullPinyin, "nihao"),
            (.microsoftDoublePinyin, "nihk"),
            (.sogouDoublePinyin, "nihk")
        ]

        for (schema, keys) in vectors {
            bridge.clearComposition()
            XCTAssertTrue(bridge.selectSchema(schema.rawValue), schema.displayName)
            let startedAt = ProcessInfo.processInfo.systemUptime
            for scalar in keys.utf8 {
                XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0))
            }
            let snapshot = bridge.snapshot(withCandidateLimit: 100)
            XCTAssertLessThan(
                ProcessInfo.processInfo.systemUptime - startedAt,
                0.35,
                "\(schema.displayName) first candidates exceeded 350 ms"
            )
            XCTAssertFalse(snapshot.preedit.isEmpty, schema.displayName)
            XCTAssertTrue(
                snapshot.candidates.contains(where: { $0.text == "你好" }),
                "\(schema.displayName) candidates: \(snapshot.candidates.map(\.text).prefix(20))"
            )
            if schema == .fullPinyin,
               let hello = snapshot.candidates.first(where: { $0.text == "你好" }) {
                XCTAssertTrue(bridge.selectCandidate(at: hello.index))
                XCTAssertEqual(
                    bridge.snapshot(withCandidateLimit: 10).commitText,
                    "你好"
                )
            }
        }

        // Incomplete multi-syllable input should keep phrase completions and
        // still expose first-syllable characters (PC-IME progressive style).
        bridge.clearComposition()
        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))
        for scalar in "zhongg".utf8 {
            XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0))
        }
        let zhongg = bridge.snapshot(withCandidateLimit: 160)
        XCTAssertTrue(
            zhongg.candidates.contains(where: { $0.text == "中国" }),
            "zhongg phrases: \(zhongg.candidates.map(\.text).prefix(30))"
        )
        XCTAssertTrue(
            zhongg.candidates.contains(where: { $0.text == "中" }),
            "zhongg should keep first-syllable 中: \(zhongg.candidates.map(\.text).prefix(40))"
        )
        if let china = zhongg.candidates.firstIndex(where: { $0.text == "中国" }),
           let zhong = zhongg.candidates.firstIndex(where: { $0.text == "中" }) {
            XCTAssertLessThan(china, zhong, "phrases should precede first-syllable chars")
        }
        XCTAssertGreaterThanOrEqual(zhongg.candidates.count, 40)

        bridge.clearComposition()
        for scalar in "zhao".utf8 {
            XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0))
        }
        let zhao = bridge.snapshot(withCandidateLimit: 160)
        XCTAssertGreaterThanOrEqual(
            zhao.candidates.count,
            40,
            "zhao candidates: \(zhao.candidates.map(\.text).prefix(20))"
        )

        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))
        let phraseVectors = [
            ("rengongzhineng", "人工智能"),
            ("yuyinshuru", "语音输入"),
            ("zhonghuarenmingongheguo", "中华人民共和国")
        ]
        for (keys, expected) in phraseVectors {
            bridge.clearComposition()
            for scalar in keys.utf8 {
                XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0))
            }
            let snapshot = bridge.snapshot(withCandidateLimit: 100)
            XCTAssertTrue(
                snapshot.candidates.contains(where: { $0.text == expected }),
                "\(keys) candidates: \(snapshot.candidates.map(\.text).prefix(20))"
            )
        }
        bridge.finalizeRuntime()

        let userFiles = fileManager.enumerator(atPath: user.path)?
            .compactMap { $0 as? String } ?? []
        XCTAssertTrue(userFiles.contains(where: { $0.contains("userdb") }))

        // Redeploy with one fuzzy pair and verify it affects actual Rime
        // candidates rather than just generated YAML.
        for schema in TypingInputSchema.allCases {
            try RimeSchemaGenerator.schema(for: schema, fuzzyPairs: [.nL]).write(
                to: shared.appendingPathComponent("\(schema.rawValue).schema.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }
        let fuzzyDeployer = OSGRimeBridge(
            sharedDataDirectory: shared.path,
            userDataDirectory: user.path,
            distributionVersion: "tests-fuzzy"
        )
        try fuzzyDeployer.deploy(withFullCheck: true)
        fuzzyDeployer.finalizeRuntime()

        let fuzzyBridge = OSGRimeBridge(
            sharedDataDirectory: shared.path,
            userDataDirectory: user.path,
            distributionVersion: "tests-fuzzy"
        )
        try fuzzyBridge.start()
        XCTAssertTrue(fuzzyBridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))
        for scalar in "lihao".utf8 {
            XCTAssertTrue(fuzzyBridge.processKeyCode(Int32(scalar), modifiers: 0))
        }
        let fuzzySnapshot = fuzzyBridge.snapshot(withCandidateLimit: 100)
        XCTAssertTrue(
            fuzzySnapshot.candidates.contains(where: { $0.text == "你好" }),
            "n/l fuzzy candidates: \(fuzzySnapshot.candidates.map(\.text).prefix(20))"
        )
        fuzzyBridge.finalizeRuntime()
    }

    func testPersonalDictionarySidecarPinsSameCodeCandidates() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OSGRimePersonal-\(UUID().uuidString)", isDirectory: true)
        let shared = root.appendingPathComponent("SharedSupport", isDirectory: true)
        let user = root.appendingPathComponent("UserData", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: user, withIntermediateDirectories: true)

        let bundle = Bundle(for: LibrimeIntegrationTests.self)
        let dictionaryURL = try XCTUnwrap(
            bundle.url(forResource: "osg_pinyin.dict", withExtension: "yaml")
        )
        let baseline = try String(contentsOf: dictionaryURL, encoding: .utf8)
        let patched = RimePersonalDictionaryExporter.injectingImportTables(into: baseline)
        try patched.write(
            to: shared.appendingPathComponent("osg_pinyin.dict.yaml"),
            atomically: true,
            encoding: .utf8
        )

        // Unique personal phrase on a common code — must outrank baseline “你好”.
        let personalYAML = RimePersonalDictionaryExporter.yaml(
            entries: [
                .init(text: "尼好专名", code: "ni hao"),
                .init(text: "ChatGPT", code: "chatgpt")
            ]
        )
        try personalYAML.write(
            to: shared.appendingPathComponent("osg_personal.dict.yaml"),
            atomically: true,
            encoding: .utf8
        )

        try RimeSchemaGenerator.defaultConfiguration().write(
            to: shared.appendingPathComponent("default.yaml"),
            atomically: true,
            encoding: .utf8
        )
        for schema in TypingInputSchema.allCases {
            try RimeSchemaGenerator.schema(for: schema, fuzzyPairs: []).write(
                to: shared.appendingPathComponent("\(schema.rawValue).schema.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }

        let deployer = OSGRimeBridge(
            sharedDataDirectory: shared.path,
            userDataDirectory: user.path,
            distributionVersion: "tests-personal"
        )
        try deployer.deploy(withFullCheck: true)
        deployer.finalizeRuntime()

        let bridge = OSGRimeBridge(
            sharedDataDirectory: shared.path,
            userDataDirectory: user.path,
            distributionVersion: "tests-personal"
        )
        try bridge.start()
        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))

        for scalar in "nihao".utf8 {
            XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0))
        }
        let chinese = bridge.snapshot(withCandidateLimit: 40)
        XCTAssertTrue(
            chinese.candidates.contains(where: { $0.text == "尼好专名" }),
            "personal Chinese missing: \(chinese.candidates.map(\.text).prefix(20))"
        )
        if let personal = chinese.candidates.firstIndex(where: { $0.text == "尼好专名" }),
           let baselineHello = chinese.candidates.firstIndex(where: { $0.text == "你好" }) {
            XCTAssertLessThan(personal, baselineHello, "personal same-code should pin above baseline")
        }

        bridge.clearComposition()
        for scalar in "chatgpt".utf8 {
            XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0))
        }
        let english = bridge.snapshot(withCandidateLimit: 40)
        XCTAssertTrue(
            english.candidates.contains(where: { $0.text == "ChatGPT" }),
            "personal English missing: \(english.candidates.map(\.text).prefix(20))"
        )
        bridge.finalizeRuntime()
    }
}
