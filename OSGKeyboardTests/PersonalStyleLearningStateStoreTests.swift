// PersonalStyleLearningStateStoreTests.swift
// OSGKeyboard · Tests
//
// Verifies the device-local prior only applies to the exact saved generation.

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class PersonalStyleLearningStateStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: PersonalStyleLearningStateStore!

    override func setUp() {
        super.setUp()
        suiteName = "com.osgkeyboard.personal-style-state.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = PersonalStyleLearningStateStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSavedPriorMatchesSamePackAndGeneration() {
        let pack = Self.pack(id: "user.style", generatedAt: Date(timeIntervalSince1970: 100))
        store.save(Self.prior, for: pack)

        XCTAssertEqual(store.prior(for: pack), Self.prior)
    }

    func testPriorSurvivesManualEditThatKeepsMetadata() {
        let pack = Self.pack(id: "user.style", generatedAt: Date(timeIntervalSince1970: 100))
        store.save(Self.prior, for: pack)
        var edited = pack
        edited.prompt = "# 角色\n手动修改\n# 风格边界\n自然\n# 示例\n输入 → 输出"

        XCTAssertEqual(store.prior(for: edited), Self.prior)
    }

    func testPriorIsIgnoredForAnotherGenerationOrPack() {
        store.save(
            Self.prior,
            for: Self.pack(id: "user.style", generatedAt: Date(timeIntervalSince1970: 100))
        )

        XCTAssertNil(
            store.prior(
                for: Self.pack(id: "user.style", generatedAt: Date(timeIntervalSince1970: 500))
            )
        )
        XCTAssertNil(
            store.prior(
                for: Self.pack(id: "user.other", generatedAt: Date(timeIntervalSince1970: 100))
            )
        )
        XCTAssertNil(store.prior(for: PolishStylePack(id: "user.style", name: "Legacy", prompt: "p")))
    }

    func testClearRemovesPrior() {
        let pack = Self.pack(id: "user.style", generatedAt: Date(timeIntervalSince1970: 100))
        store.save(Self.prior, for: pack)
        store.clear()

        XCTAssertNil(store.prior(for: pack))
    }

    private static let prior = PolishStyleLearningPriorEvidence(
        asr: .init(
            traits: [
                .init(name: "简短直接", description: "反复使用短句", confidence: 0.7, supportCount: 3)
            ],
            contradictions: []
        ),
        reply: .init(traits: [], contradictions: []),
        learnedThrough: Date(timeIntervalSince1970: 90),
        cumulativeASRExampleCount: 5,
        cumulativeASREffectiveCharacterCount: 2_500,
        cumulativeReplyExampleCount: 0,
        cumulativeReplyFinalEditCount: 0
    )

    private static func pack(id: String, generatedAt: Date) -> PolishStylePack {
        PolishStylePack(
            id: id,
            name: "我的说话风格",
            prompt: "# 角色\n自然\n# 风格边界\n自然\n# 示例\n输入 → 输出",
            learningMetadata: PolishStylePack.LearningMetadata(
                schemaVersion: 4,
                evidenceStatus: "sufficient",
                confidence: 0.8,
                asrExampleCount: 5,
                asrEffectiveCharacterCount: 2_500,
                replyExampleCount: 0,
                replyFinalEditCount: 0,
                generatedAt: generatedAt
            )
        )
    }
}
