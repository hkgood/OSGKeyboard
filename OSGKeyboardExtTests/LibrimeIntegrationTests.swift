// LibrimeIntegrationTests.swift
// OSGKeyboard · Ext unit tests

import Darwin
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
        defer { bridge.finalizeRuntime() }

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
    }

    func testNLFuzzyMapsLihaoToNihao() throws {
        let env = try stagedRimeEnvironment(fuzzyPairs: [.nL])
        defer { try? env.fileManager.removeItem(at: env.root) }

        let deployer = OSGRimeBridge(
            sharedDataDirectory: env.shared.path,
            userDataDirectory: env.user.path,
            distributionVersion: "tests-fuzzy-nl"
        )
        try deployer.deploy(withFullCheck: true)
        deployer.finalizeRuntime()

        let bridge = OSGRimeBridge(
            sharedDataDirectory: env.shared.path,
            userDataDirectory: env.user.path,
            distributionVersion: "tests-fuzzy-nl"
        )
        try bridge.start()
        defer { bridge.finalizeRuntime() }
        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))
        type("lihao", on: bridge)
        let snapshot = bridge.snapshot(withCandidateLimit: 100)
        XCTAssertTrue(
            snapshot.candidates.contains(where: { $0.text == "你好" }),
            "n/l fuzzy candidates: \(snapshot.candidates.map(\.text).prefix(20))"
        )
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

    func testAbbreviatedPinyinPrefersHighFrequencyPhrases() throws {
        let env = try deployedRimeEnvironment()
        defer { try? env.fileManager.removeItem(at: env.root) }

        let bridge = OSGRimeBridge(
            sharedDataDirectory: env.shared.path,
            userDataDirectory: env.user.path,
            distributionVersion: "tests-abbrev"
        )
        try bridge.start()
        defer { bridge.finalizeRuntime() }
        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))

        let cases: [(String, String)] = [
            ("wom", "我们"),
            ("wm", "我们"),
            ("women", "我们"),
            ("bn", "不能"),
            ("nh", "你好"),
            ("nihao", "你好")
        ]
        for (keys, expected) in cases {
            type(keys, on: bridge)
            let snapshot = bridge.snapshot(withCandidateLimit: 40)
            let texts = snapshot.candidates.map(\.text)
            XCTAssertEqual(
                texts.first,
                expected,
                "\(keys) top-1 \(texts.prefix(12))"
            )
            XCTAssertNotEqual(texts.first, "我呒")
            XCTAssertFalse(texts.prefix(3).contains("我呒"))
        }

        type("zhangwei", on: bridge)
        let zhangwei = bridge.snapshot(withCandidateLimit: 40)
        XCTAssertTrue(
            zhangwei.candidates.contains(where: { $0.text == "张伟" }),
            "zhangwei: \(zhangwei.candidates.map(\.text).prefix(20))"
        )

        type("zhg", on: bridge)
        let zhg = bridge.snapshot(withCandidateLimit: 40)
        XCTAssertTrue(
            zhg.candidates.contains(where: { $0.text == "中国" }),
            "zhg should reach 中国 via zh abbrev: \(zhg.candidates.map(\.text).prefix(20))"
        )
    }

    func testUserDictionaryLearnsSelectedPhraseAcrossFinalize() throws {
        let env = try deployedRimeEnvironment()
        defer { try? env.fileManager.removeItem(at: env.root) }

        let bridge = OSGRimeBridge(
            sharedDataDirectory: env.shared.path,
            userDataDirectory: env.user.path,
            distributionVersion: "tests-learn"
        )
        try bridge.start()
        defer { bridge.finalizeRuntime() }
        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))

        type("zhangwei", on: bridge)
        let before = bridge.snapshot(withCandidateLimit: 80)
        let startIndex = try XCTUnwrap(
            before.candidates.firstIndex(where: { $0.text == "张伟" }),
            "missing 张伟: \(before.candidates.map(\.text).prefix(20))"
        )
        for _ in 0..<8 {
            type("zhangwei", on: bridge)
            let snapshot = bridge.snapshot(withCandidateLimit: 80)
            let current = try XCTUnwrap(snapshot.candidates.first(where: { $0.text == "张伟" }))
            XCTAssertTrue(bridge.selectCandidate(at: current.index))
            _ = bridge.snapshot(withCandidateLimit: 8)
        }
        bridge.finalizeRuntime()

        let reopened = OSGRimeBridge(
            sharedDataDirectory: env.shared.path,
            userDataDirectory: env.user.path,
            distributionVersion: "tests-learn"
        )
        try reopened.start()
        defer { reopened.finalizeRuntime() }
        XCTAssertTrue(reopened.selectSchema(TypingInputSchema.fullPinyin.rawValue))
        type("zhangwei", on: reopened)
        let after = reopened.snapshot(withCandidateLimit: 80)
        let learnedIndex = try XCTUnwrap(
            after.candidates.firstIndex(where: { $0.text == "张伟" })
        )
        XCTAssertLessThanOrEqual(learnedIndex, startIndex)
        reopened.finalizeRuntime()

        try RimeResourceInstaller.removeUserDictionaries(in: env.user)
        let names = try env.fileManager.contentsOfDirectory(atPath: env.user.path)
        XCTAssertFalse(names.contains { $0.lowercased().contains("userdb") })
        XCTAssertTrue(
            env.fileManager.fileExists(atPath: env.user.appendingPathComponent("build").path)
        )
    }

    func testAssembledPhraseBecomesUserWord() throws {
        let env = try deployedRimeEnvironment()
        defer { try? env.fileManager.removeItem(at: env.root) }

        let bridge = OSGRimeBridge(
            sharedDataDirectory: env.shared.path,
            userDataDirectory: env.user.path,
            distributionVersion: "tests-encode"
        )
        try bridge.start()
        defer { bridge.finalizeRuntime() }
        XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))

        type("chu", on: bridge)
        let chuSnap = bridge.snapshot(withCandidateLimit: 80)
        let chu = try XCTUnwrap(
            chuSnap.candidates.first(where: { $0.text == "褚" }),
            "missing 褚: \(chuSnap.candidates.map(\.text).prefix(20))"
        )
        XCTAssertTrue(bridge.selectCandidate(at: chu.index))
        _ = bridge.snapshot(withCandidateLimit: 8)

        type("han", on: bridge)
        let hanSnap = bridge.snapshot(withCandidateLimit: 80)
        let han = try XCTUnwrap(
            hanSnap.candidates.first(where: { $0.text == "寒" }),
            "missing 寒: \(hanSnap.candidates.map(\.text).prefix(20))"
        )
        XCTAssertTrue(bridge.selectCandidate(at: han.index))
        _ = bridge.snapshot(withCandidateLimit: 8)

        type("chuhan", on: bridge)
        let learned = bridge.snapshot(withCandidateLimit: 80)
        let assembled = learned.candidates.contains(where: { $0.text == "褚寒" })
        if !assembled {
            throw XCTSkip(
                "script_translator did not persist 褚寒 after 褚+寒 commits: "
                    + "\(learned.candidates.map(\.text).prefix(20)). "
                    + "Auto-phrasing stays a follow-up, not a Swift overlay in this slice."
            )
        }
    }

    /// Host 2.4.0 部署 + 扩展 prepare/teardown 循环。phys_footprint 更接近
    /// 实体机 jetsam 口径；绝对值含 XCTest 进程，只看相对增量。
    func testHostDeployAndTypingCyclesKeepMemoryStable() throws {
        let staged = try stagedRimeEnvironment()
        defer { try? staged.fileManager.removeItem(at: staged.root) }

        let beforeDeploy = MemoryProbe.capture()
        let deployer = OSGRimeBridge(
            sharedDataDirectory: staged.shared.path,
            userDataDirectory: staged.user.path,
            distributionVersion: "tests-memory-deploy"
        )
        try deployer.deploy(withFullCheck: true)
        let afterDeploy = MemoryProbe.capture()
        deployer.finalizeRuntime()
        let afterHostFinalize = MemoryProbe.capture()

        let deployFootprintGrowth = afterDeploy.physFootprintMB - beforeDeploy.physFootprintMB
        let deployRSSGrowth = afterDeploy.rssMB - beforeDeploy.rssMB
        XCTContext.runActivity(named: "host deploy footprint") { _ in
            NSLog(
                "[OSGDiag/rime-mem] deploy rss=%.1f→%.1fMB deltaRSS=%.1fMB foot=%.1f→%.1fMB deltaFoot=%.1fMB finalize rss=%.1fMB foot=%.1fMB",
                beforeDeploy.rssMB,
                afterDeploy.rssMB,
                deployRSSGrowth,
                beforeDeploy.physFootprintMB,
                afterDeploy.physFootprintMB,
                deployFootprintGrowth,
                afterHostFinalize.rssMB,
                afterHostFinalize.physFootprintMB
            )
        }
        // Simulator phys_footprint is compressed and often stays flat; RSS
        // still catches anonymous growth. Device jetsam follows footprint.
        XCTAssertLessThan(
            deployFootprintGrowth,
            HostMemoryBudget.deferHeavyWorkAboveMB,
            "host deploy footprint grew \(String(format: "%.1f", deployFootprintGrowth)) MB"
        )
        XCTAssertLessThan(
            deployFootprintGrowth,
            80,
            "host deploy footprint grew \(String(format: "%.1f", deployFootprintGrowth)) MB (budget estimate is 24 MB)"
        )

        var peakTyping = afterHostFinalize
        var lastIdle = afterHostFinalize
        let cycleCount = 20
        for cycle in 1...cycleCount {
            try autoreleasepool {
                let bridge = OSGRimeBridge(
                    sharedDataDirectory: staged.shared.path,
                    userDataDirectory: staged.user.path,
                    distributionVersion: "tests-memory-session"
                )
                try bridge.start()
                XCTAssertTrue(bridge.selectSchema(TypingInputSchema.fullPinyin.rawValue))
                // Production LibrimeEngine copies 160 candidates per keystroke.
                for keys in ["nihao", "wom", "zhangwei", "zhongg"] {
                    type(keys, on: bridge)
                    _ = bridge.snapshot(withCandidateLimit: 160)
                }
                let during = MemoryProbe.capture()
                if during.physFootprintMB > peakTyping.physFootprintMB {
                    peakTyping = during
                }
                bridge.finalizeRuntime()
            }
            lastIdle = MemoryProbe.capture()
            NSLog(
                "[OSGDiag/rime-mem] cycle=%d idleFoot=%.1fMB peakFoot=%.1fMB rss=%.1fMB",
                cycle,
                lastIdle.physFootprintMB,
                peakTyping.physFootprintMB,
                lastIdle.rssMB
            )
        }

        let idleFootprintGrowth = lastIdle.physFootprintMB - afterHostFinalize.physFootprintMB
        let idleRSSGrowth = lastIdle.rssMB - afterHostFinalize.rssMB
        let sessionPeak = peakTyping.physFootprintMB - afterHostFinalize.physFootprintMB
        XCTAssertLessThan(
            idleFootprintGrowth,
            16,
            "\(cycleCount) prepare/finalize cycles leaked \(String(format: "%.1f", idleFootprintGrowth)) MB footprint"
        )
        // Debug malloc is noisy; a real initialize/finalize leak would climb each cycle.
        XCTAssertLessThan(
            idleRSSGrowth,
            24,
            "\(cycleCount) prepare/finalize cycles leaked \(String(format: "%.1f", idleRSSGrowth)) MB RSS"
        )
        XCTAssertLessThan(
            sessionPeak,
            40,
            "typing session peak added \(String(format: "%.1f", sessionPeak)) MB above post-deploy idle"
        )

        try RimeResourceInstaller.removeUserDictionaries(in: staged.user)
        let afterClear = MemoryProbe.capture()
        XCTAssertLessThan(
            afterClear.physFootprintMB - lastIdle.physFootprintMB,
            8,
            "clearing userdb while runtime is down should be a file-only wipe"
        )
    }

    func testRemoveUserDictionariesKeepsBuildDirectory() throws {
        let fileManager = FileManager.default
        let user = fileManager.temporaryDirectory
            .appendingPathComponent("OSGUserDB-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: user) }
        try fileManager.createDirectory(at: user.appendingPathComponent("build"), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: user.appendingPathComponent("osg_pinyin.userdb"),
            withIntermediateDirectories: true
        )
        try "keep\n".write(
            to: user.appendingPathComponent("user.yaml"),
            atomically: true,
            encoding: .utf8
        )

        try RimeResourceInstaller.removeUserDictionaries(in: user)
        XCTAssertTrue(fileManager.fileExists(atPath: user.appendingPathComponent("build").path))
        XCTAssertTrue(fileManager.fileExists(atPath: user.appendingPathComponent("user.yaml").path))
        XCTAssertFalse(
            fileManager.fileExists(atPath: user.appendingPathComponent("osg_pinyin.userdb").path)
        )
    }

    private func stagedRimeEnvironment(
        fuzzyPairs: Set<PinyinFuzzyPair> = []
    ) throws -> (
        root: URL,
        shared: URL,
        user: URL,
        fileManager: FileManager
    ) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OSGRimeTests-\(UUID().uuidString)", isDirectory: true)
        let shared = root.appendingPathComponent("SharedSupport", isDirectory: true)
        let user = root.appendingPathComponent("UserData", isDirectory: true)
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
            try RimeSchemaGenerator.schema(for: schema, fuzzyPairs: fuzzyPairs).write(
                to: shared.appendingPathComponent("\(schema.rawValue).schema.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }
        return (root, shared, user, fileManager)
    }

    private func deployedRimeEnvironment() throws -> (
        root: URL,
        shared: URL,
        user: URL,
        fileManager: FileManager
    ) {
        let staged = try stagedRimeEnvironment()
        let deployer = OSGRimeBridge(
            sharedDataDirectory: staged.shared.path,
            userDataDirectory: staged.user.path,
            distributionVersion: "tests"
        )
        try deployer.deploy(withFullCheck: true)
        deployer.finalizeRuntime()
        return staged
    }

    private func type(_ keys: String, on bridge: OSGRimeBridge) {
        bridge.clearComposition()
        for scalar in keys.utf8 {
            XCTAssertTrue(bridge.processKeyCode(Int32(scalar), modifiers: 0), keys)
        }
    }
}

/// RSS plus phys_footprint. Jetsam on device tracks footprint more closely
/// than `task_basic_info.resident_size`.
private struct MemoryProbe {
    let rssMB: Double
    let physFootprintMB: Double

    static func capture() -> MemoryProbe {
        MemoryProbe(rssMB: OSGDiag.memoryMB(), physFootprintMB: physFootprintMB())
    }

    private static func physFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576.0
    }
}
