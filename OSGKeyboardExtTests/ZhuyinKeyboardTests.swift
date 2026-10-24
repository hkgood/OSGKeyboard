// ZhuyinKeyboardTests.swift
// OSGKeyboard · Ext unit tests

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class ZhuyinKeyboardTests: XCTestCase {
    func testDachenMappingCoversEverySymbolAndPreservesVisiblePreedit() {
        let symbols = ZhuyinKeyboardLayout.rows.flatMap { $0 }
        XCTAssertEqual(symbols.count, 41)
        XCTAssertEqual(Set(symbols).count, 41)
        let keys = symbols.compactMap { $0.first.flatMap(ZhuyinKeyboardLayout.key(for:)) }
        XCTAssertEqual(keys.count, 41)
        XCTAssertEqual(Set(keys).count, 41)
        for (symbol, key) in zip(symbols, keys) {
            XCTAssertEqual(ZhuyinKeyboardLayout.displayText(for: String(key)), symbol)
        }
        XCTAssertEqual(ZhuyinKeyboardLayout.key(for: "ㄋ"), "s")
        XCTAssertEqual(ZhuyinKeyboardLayout.key(for: "ㄡ"), ".")
        XCTAssertEqual(ZhuyinKeyboardLayout.key(for: "ㄥ"), "/")
        XCTAssertEqual(ZhuyinKeyboardLayout.key(for: "ˇ"), "3")
        XCTAssertEqual(ZhuyinKeyboardLayout.displayText(for: "su3 cl3'你好"), "ㄋㄧˇ ㄏㄠˇ'你好")
        XCTAssertNil(ZhuyinKeyboardLayout.key(for: "，"))
        XCTAssertNil(ZhuyinKeyboardLayout.key(for: "a"))
    }

    func testSchemaChoosesFourRowZhuyinWithoutChangingOtherPages() {
        let layout = StandardTypingLayout()
        let zhuyin = layout.rows(for: .letters, language: .chinese, shiftActive: true, schema: .zhuyin)
        XCTAssertEqual(zhuyin.count, 4)
        XCTAssertEqual(zhuyin.flatMap { $0 }.count, 42)
        XCTAssertEqual(zhuyin.last?.last, "⌫")
        XCTAssertFalse(zhuyin.flatMap { $0 }.contains("⇧"))

        let english = layout.rows(for: .letters, language: .english, shiftActive: true, schema: .zhuyin)
        XCTAssertEqual(english.count, 3)
        XCTAssertEqual(english.first?.first, "Q")
        let pinyin = layout.rows(for: .letters, language: .chinese, shiftActive: false, schema: .fullPinyin)
        XCTAssertEqual(pinyin.count, 3)
        XCTAssertEqual(pinyin.first?.first, "q")
        for page in [TypingKeyPage.numbers, .symbols] {
            XCTAssertEqual(
                layout.rows(for: page, language: .chinese, shiftActive: false, schema: .zhuyin),
                layout.rows(for: page, language: .chinese, shiftActive: false, schema: .fullPinyin)
            )
        }
        XCTAssertNil(PinyinNextKeyResolver.validNextKeys(
            rawInput: "su3", schema: .zhuyin, language: .chinese, page: .letters
        ))
    }

    func testFourRowsKeepBottomActionsFixedAndEveryKeyReachable() {
        let provider = StandardTypingLayout()
        let widths: [CGFloat] = [320, 393, 834, 1194]
        for width in widths {
            let metrics = TypingSurfaceMetrics.metrics(isIPad: width > 600, width: width)
            func build(_ schema: TypingInputSchema) -> TypingKeyLayout {
                let rows = provider.rows(for: .letters, language: .chinese, shiftActive: false, schema: schema)
                return TypingKeyLayoutBuilder.build(
                    size: CGSize(width: width, height: 500),
                    letterRows: rows,
                    pageSwitchLabel: "123",
                    spaceLabel: "空白",
                    returnLabel: "return",
                    metrics: metrics.fittingGrid(rowCount: rows.count),
                    includeGlobeKey: false,
                    keyWeight: { _, _, _ in 1 }
                )
            }
            let zhuyin = build(.zhuyin)
            let pinyin = build(.fullPinyin)
            XCTAssertEqual(zhuyin.bottomRowMinY, pinyin.bottomRowMinY, accuracy: 0.001)
            XCTAssertEqual(zhuyin.keyPlaneBounds.maxY, pinyin.keyPlaneBounds.maxY, accuracy: 0.001)
            XCTAssertLessThanOrEqual(zhuyin.keyPlaneBounds.maxX, width + 0.001)
            for key in zhuyin.keys {
                XCTAssertGreaterThan(key.visualFrame.width, 0)
                XCTAssertGreaterThan(key.visualFrame.height, 0)
                XCTAssertEqual(KeyHitTesting.hitTarget(
                    at: key.center,
                    targets: zhuyin.keys,
                    keyPlaneBounds: zhuyin.keyPlaneBounds,
                    horizontalGap: zhuyin.horizontalGap,
                    verticalGap: zhuyin.verticalGap
                )?.id, key.id)
            }
        }
    }

    func testFreshAndInvalidPreferencesOpenChineseZhuyin() {
        let defaults = isolatedDefaults()
        let configuration = TypingInputConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.schema, .zhuyin)
        XCTAssertEqual(configuration.defaultInputMode, .pinyin)
        XCTAssertEqual(TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults), .typing)
        XCTAssertEqual(TypingInputConfiguration.preferredTypingLanguageOnOpen(defaults: defaults), .chinese)

        defaults.set("missing-schema", forKey: "typing.input.schema")
        defaults.set("missing-mode", forKey: "typing.input.defaultInputMode")
        configuration.reload()
        XCTAssertEqual(configuration.schema, .zhuyin)
        XCTAssertEqual(configuration.defaultInputMode, .pinyin)
    }

    func testExistingPinyinAndExplicitOpenPreferencesArePreserved() {
        let defaults = isolatedDefaults()
        for schema in [TypingInputSchema.fullPinyin, .microsoftDoublePinyin, .sogouDoublePinyin] {
            defaults.set(schema.rawValue, forKey: "typing.input.schema")
            for mode in DefaultInputMode.allCases {
                defaults.set(mode.rawValue, forKey: "typing.input.defaultInputMode")
                let configuration = TypingInputConfiguration(defaults: defaults)
                XCTAssertEqual(configuration.schema, schema)
                XCTAssertEqual(configuration.defaultInputMode, mode)
            }
        }
        defaults.removeObject(forKey: "typing.input.defaultInputMode")
        defaults.set(false, forKey: "typing.input.defaultToTyping")
        XCTAssertEqual(TypingInputConfiguration(defaults: defaults).defaultInputMode, .voice)
        defaults.set(true, forKey: "typing.input.defaultToTyping")
        XCTAssertEqual(TypingInputConfiguration(defaults: defaults).defaultInputMode, .pinyin)
    }

    func testSavedPinyinLayoutDoesNotConstructEngine() {
        let defaults = isolatedDefaults()
        defaults.set(TypingInputSchema.fullPinyin.rawValue, forKey: "typing.input.schema")
        let configuration = TypingInputConfiguration(defaults: defaults)
        var creationCount = 0
        let typing = TypingSessionController(
            engine: {
                creationCount += 1
                return ZhuyinTestEngine()
            },
            configuration: configuration
        )
        XCTAssertEqual(typing.schema, .fullPinyin)
        XCTAssertEqual(typing.keyRows.first?.first, "q")
        XCTAssertEqual(creationCount, 0)
    }

    func testZhuyinSymbolsAndTonesComposeEvenWithShiftArmed() {
        let (typing, engine) = makeSession()
        _ = typing.handleKey("⇧")
        for symbol in ["ㄋ", "ㄧ", "ˇ"] {
            XCTAssertEqual(typing.handleKey(symbol), .none)
        }
        XCTAssertEqual(engine.processedCharacters, Array("ㄋㄧˇ"))
        XCTAssertTrue(engine.selectedIndices.isEmpty)
        XCTAssertEqual(typing.composition.preedit, "ㄋㄧˇ")
        XCTAssertFalse(typing.isShiftEnabled)
    }

    func testEnglishAutocapitalizationIsClearedWhenReturningToZhuyin() {
        let (typing, engine) = makeSession()
        typing.precedingTextProvider = { "" }
        typing.autocapitalizationModeProvider = { .sentences }
        _ = typing.setLanguage(.english)
        XCTAssertTrue(typing.shiftActive)
        _ = typing.setLanguage(.chinese)
        XCTAssertFalse(typing.isShiftEnabled)
        XCTAssertTrue(typing.isZhuyinLetterPage)
        XCTAssertEqual(typing.handleKey("ㄋ"), .none)
        XCTAssertEqual(engine.processedCharacters, ["ㄋ"])
    }

    func testNumericPageCommitsChineseBeforeInsertingTheRequestedDigit() {
        let (typing, engine) = makeSession()
        _ = typing.handleKey("ㄋ")
        typing.setPage(.numbers)
        XCTAssertEqual(typing.handleKey("2"), .insert("你2"))
        XCTAssertEqual(engine.selectedIndices, [7])
        XCTAssertTrue(typing.composition.preedit.isEmpty)
        XCTAssertEqual(typing.handleKey("注音"), .none)
        XCTAssertTrue(typing.isZhuyinLetterPage)
    }

    func testCandidateTapUsesTheEngineIndexRatherThanDisplayPosition() {
        let (typing, engine) = makeSession()
        _ = typing.handleKey("ㄋ")
        XCTAssertEqual(typing.selectCandidate(at: 1), .insert("妳"))
        XCTAssertEqual(engine.selectedIndices, [11])
    }

    func testIPadPunctuationCommitsAllSegmentsBeforeLiteral() {
        let (typing, engine) = makeSession()
        _ = typing.handleKey("ㄋ")
        engine.compositionAfterNextSelection = TypingComposition(
            preedit: "ㄏㄠˇ", rawInput: "cl3",
            candidates: [TypingCandidate(text: "好", engineIndex: 8)]
        )
        XCTAssertEqual(typing.handleKey("，"), .insert("你好，"))
        XCTAssertEqual(engine.selectedIndices, [7, 8])
        XCTAssertTrue(typing.composition.preedit.isEmpty)
    }

    func testNumberPageSlashIsLiteralRatherThanDachenFinal() {
        let (typing, engine) = makeSession()
        _ = typing.handleKey("ㄋ")
        typing.setPage(.numbers)
        XCTAssertEqual(typing.handleKey("/"), .insert("你/"))
        XCTAssertEqual(engine.processedCharacters, ["ㄋ"])
        XCTAssertTrue(typing.composition.preedit.isEmpty)
    }

    func testUnmatchedPhoneticTailIsPreservedBeforePunctuation() {
        let (typing, engine) = makeSession()
        _ = typing.handleKey("ㄋ")
        _ = typing.handleKey("ㄧ")
        engine.composition = TypingComposition(preedit: "ㄋㄧ", rawInput: "su", candidates: [])
        XCTAssertEqual(typing.handleKey("。"), .insert("ㄋㄧ。"))
        XCTAssertTrue(engine.selectedIndices.isEmpty)
        XCTAssertTrue(typing.composition.preedit.isEmpty)
    }

    func testActiveSchemaReloadPreservesPreeditAndReusesPreparedEngine() async {
        let defaults = isolatedDefaults()
        let configuration = TypingInputConfiguration(defaults: defaults)
        let engine = ZhuyinTestEngine()
        let prepared = expectation(description: "engine prepared")
        engine.onPrepare = { prepared.fulfill() }
        let typing = TypingSessionController(
            engine: { engine },
            configuration: configuration,
            hostHeavyProvider: { false }
        )
        typing.enterTypingMode()
        await fulfillment(of: [prepared], timeout: 1)
        await Task.yield()
        for symbol in ["ㄋ", "ㄧ", "ˇ"] { _ = typing.handleKey(symbol) }

        defaults.set(TypingInputSchema.fullPinyin.rawValue, forKey: "typing.input.schema")
        XCTAssertEqual(typing.reloadInputConfiguration(), .insert("ㄋㄧˇ"))
        XCTAssertEqual(typing.schema, .fullPinyin)
        XCTAssertEqual(typing.keyRows.count, 3)
        XCTAssertEqual(typing.keyRows.first?.first, "q")
        XCTAssertEqual(engine.prepareCallCount, 1)
        XCTAssertEqual(engine.selectedSchemas, [.fullPinyin])
        XCTAssertTrue(typing.engineReady)
        XCTAssertTrue(typing.composition.preedit.isEmpty)
        XCTAssertEqual(typing.reloadInputConfiguration(), .none)
        typing.leaveTypingMode()
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ZhuyinKeyboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeSession() -> (TypingSessionController, ZhuyinTestEngine) {
        let engine = ZhuyinTestEngine()
        return (TypingSessionController(
            engine: { engine },
            configuration: TypingInputConfiguration(defaults: isolatedDefaults()),
            hostHeavyProvider: { false }
        ), engine)
    }
}

@MainActor
private final class ZhuyinTestEngine: RimeEngineBridging {
    var composition: TypingComposition = .empty
    var isReady = false
    var schema: TypingInputSchema = .zhuyin
    var processedCharacters: [Character] = []
    var selectedIndices: [Int] = []
    var selectedSchemas: [TypingInputSchema] = []
    var compositionAfterNextSelection: TypingComposition?
    var prepareCallCount = 0
    var onPrepare: (() -> Void)?

    func prepare() async throws {
        isReady = true
        prepareCallCount += 1
        onPrepare?()
    }

    func teardown() {
        composition = .empty
        isReady = false
    }

    func setLanguage(_ language: TypingInputLanguage) {
        if language == .english { composition = .empty }
    }

    func setSchema(_ schema: TypingInputSchema) -> Bool {
        selectedSchemas.append(schema)
        self.schema = schema
        composition = .empty
        return true
    }

    func processCharacter(_ character: Character) -> String? {
        processedCharacters.append(character)
        let raw = composition.rawInput + String(ZhuyinKeyboardLayout.key(for: character) ?? character)
        composition = TypingComposition(
            preedit: ZhuyinKeyboardLayout.displayText(for: raw), rawInput: raw,
            candidates: [
                TypingCandidate(text: "你", engineIndex: 7),
                TypingCandidate(text: "妳", engineIndex: 11)
            ]
        )
        return nil
    }

    func processBackspace() -> String? {
        composition = .empty
        return nil
    }
    func processSpace() -> String? { selectCandidate(at: 7) }
    func processReturn() -> String? { selectCandidate(at: 7) }

    func selectCandidate(at index: Int) -> String {
        selectedIndices.append(index)
        let text = composition.candidates.first { $0.engineIndex == index }?.text ?? ""
        composition = compositionAfterNextSelection ?? .empty
        compositionAfterNextSelection = nil
        return text
    }

    func flushPreedit() -> String {
        let text = schema == .zhuyin
            ? ZhuyinKeyboardLayout.displayText(for: composition.rawInput) : composition.rawInput
        composition = .empty
        return text
    }

    func clearComposition() { composition = .empty }
}
