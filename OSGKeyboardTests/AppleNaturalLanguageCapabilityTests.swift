// AppleNaturalLanguageCapabilityTests.swift
// OSGKeyboardTests
//
// Exploratory, fully on-device evaluation for Apple's traditional Natural
// Language APIs. This intentionally does not use Foundation Models or network.

import Foundation
import NaturalLanguage
import XCTest

final class AppleNaturalLanguageCapabilityTests: XCTestCase {
    private struct LanguageSample {
        let id: String
        let text: String
        let expectedLanguage: String?
        let isClear: Bool
    }

    private struct LanguageHypothesis: Codable {
        let language: String
        let probability: Double
    }

    private struct LanguageResult: Codable {
        let id: String
        let text: String
        let expectedLanguage: String?
        let dominantLanguage: String?
        let confidence: Double
        let correct: Bool?
        let hypotheses: [LanguageHypothesis]
    }

    private struct EntityExpectation {
        let text: String
        let tag: NLTag
    }

    private struct EntitySample {
        let id: String
        let text: String
        let language: NLLanguage
        let expected: [EntityExpectation]
    }

    private struct EntityMatch: Codable {
        let text: String
        let tag: String
    }

    private struct EntityResult: Codable {
        let id: String
        let text: String
        let expected: [EntityMatch]
        let detected: [EntityMatch]
        let matchedCount: Int
        let exactMatchedCount: Int
    }

    private struct DetectorSample {
        let id: String
        let text: String
        let expectedTypes: Set<String>
    }

    private struct DetectorMatch: Codable {
        let type: String
        let text: String
    }

    private struct DetectorResult: Codable {
        let id: String
        let text: String
        let expectedTypes: [String]
        let detected: [DetectorMatch]
        let matchedTypes: [String]
    }

    private struct SemanticAnchor {
        let skillID: String
        let examples: [String]
    }

    private struct SemanticSample {
        let id: String
        let text: String
        let expectedSkillID: String
        let isAdversarial: Bool
    }

    private struct SemanticCorpus {
        let language: NLLanguage
        let languageID: String
        let anchors: [SemanticAnchor]
        let samples: [SemanticSample]
    }

    private struct SkillDistance: Codable {
        let skillID: String
        let distance: Double
    }

    private struct SemanticResult: Codable {
        let id: String
        let text: String
        let expectedSkillID: String
        let predictedSkillID: String?
        let topThree: [SkillDistance]
        let topOneCorrect: Bool
        let topThreeCorrect: Bool
        let isAdversarial: Bool
    }

    private struct SemanticControl {
        let id: String
        let query: String
        let related: String
        let unrelated: String
    }

    private struct SemanticControlResult: Codable {
        let id: String
        let relatedDistance: Double?
        let unrelatedDistance: Double?
        let passed: Bool
    }

    private struct SemanticLanguageReport: Codable {
        let language: String
        let embeddingAvailable: Bool
        let dimension: Int?
        let revision: Int?
        let controlAccuracy: Double?
        let topOneAccuracy: Double?
        let topThreeAccuracy: Double?
        let regularTopOneAccuracy: Double?
        let adversarialTopOneAccuracy: Double?
        let controls: [SemanticControlResult]
        let results: [SemanticResult]
    }

    private struct LatencyReport: Codable {
        let operation: String
        let iterations: Int
        let averageMilliseconds: Double
    }

    private struct EvaluationReport: Codable {
        let osVersion: String
        let languageClearAccuracy: Double
        let languageResults: [LanguageResult]
        let entityLooseRecall: Double
        let entityExactRecall: Double
        let entityResults: [EntityResult]
        let detectorRecall: Double
        let detectorResults: [DetectorResult]
        let semanticReports: [SemanticLanguageReport]
        let latency: [LatencyReport]
    }

    func testAppleNaturalLanguageCapability() throws {
        let languageResults = evaluateLanguages()
        let entityResults = evaluateEntities()
        let detector = try makeDataDetector()
        let detectorResults = evaluateDataDetection(using: detector)
        let semanticCorpora = makeSemanticCorpora()
        let semanticReports = semanticCorpora.map(evaluateSemantics)

        let clearLanguageResults = languageResults.compactMap(\.correct)
        let languageAccuracy = ratio(
            numerator: clearLanguageResults.filter { $0 }.count,
            denominator: clearLanguageResults.count
        )
        let expectedEntityCount = entityResults.reduce(0) { $0 + $1.expected.count }
        let matchedEntityCount = entityResults.reduce(0) { $0 + $1.matchedCount }
        let exactMatchedEntityCount = entityResults.reduce(0) {
            $0 + $1.exactMatchedCount
        }
        let expectedDetectorCount = detectorResults.reduce(0) { $0 + $1.expectedTypes.count }
        let matchedDetectorCount = detectorResults.reduce(0) { $0 + $1.matchedTypes.count }

        let report = EvaluationReport(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            languageClearAccuracy: languageAccuracy,
            languageResults: languageResults,
            entityLooseRecall: ratio(
                numerator: matchedEntityCount,
                denominator: expectedEntityCount
            ),
            entityExactRecall: ratio(
                numerator: exactMatchedEntityCount,
                denominator: expectedEntityCount
            ),
            entityResults: entityResults,
            detectorRecall: ratio(
                numerator: matchedDetectorCount,
                denominator: expectedDetectorCount
            ),
            detectorResults: detectorResults,
            semanticReports: semanticReports,
            latency: benchmark(detector: detector, semanticCorpora: semanticCorpora)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // One stable marker lets the command-line runner extract the complete report.
        print("APPLE_NL_EVAL_JSON_BEGIN")
        print(json)
        print("APPLE_NL_EVAL_JSON_END")

        XCTAssertFalse(languageResults.isEmpty)
        XCTAssertFalse(entityResults.isEmpty)
        XCTAssertFalse(detectorResults.isEmpty)
        XCTAssertEqual(semanticReports.count, semanticCorpora.count)
    }

    private func evaluateLanguages() -> [LanguageResult] {
        makeLanguageSamples().map { sample in
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(sample.text)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
                .map {
                    LanguageHypothesis(
                        language: $0.key.rawValue,
                        probability: rounded($0.value)
                    )
                }
                .sorted { $0.probability > $1.probability }
            let dominant = recognizer.dominantLanguage?.rawValue
            let confidence = hypotheses.first(where: { $0.language == dominant })?.probability ?? 0
            return LanguageResult(
                id: sample.id,
                text: sample.text,
                expectedLanguage: sample.expectedLanguage,
                dominantLanguage: dominant,
                confidence: confidence,
                correct: sample.isClear
                    ? dominant == sample.expectedLanguage
                    : nil,
                hypotheses: hypotheses
            )
        }
    }

    private func makeLanguageSamples() -> [LanguageSample] {
        [
            LanguageSample(
                id: "zh-clear",
                text: "请把会议纪要整理后发给产品和设计团队。",
                expectedLanguage: "zh-Hans",
                isClear: true
            ),
            LanguageSample(
                id: "en-clear",
                text: "Please send the revised proposal before Friday afternoon.",
                expectedLanguage: "en",
                isClear: true
            ),
            LanguageSample(
                id: "ja-clear",
                text: "来週の会議資料を金曜日までに送ってください。",
                expectedLanguage: "ja",
                isClear: true
            ),
            LanguageSample(
                id: "ko-clear",
                text: "다음 주 회의 자료를 금요일까지 보내 주세요.",
                expectedLanguage: "ko",
                isClear: true
            ),
            LanguageSample(
                id: "fr-clear",
                text: "Veuillez envoyer la proposition révisée avant vendredi.",
                expectedLanguage: "fr",
                isClear: true
            ),
            LanguageSample(
                id: "es-clear",
                text: "Por favor, envía la propuesta revisada antes del viernes.",
                expectedLanguage: "es",
                isClear: true
            ),
            LanguageSample(
                id: "zh-mixed",
                text: "请 review 一下这个 PR，确认 API response 有没有 breaking change。",
                expectedLanguage: nil,
                isClear: false
            ),
            LanguageSample(
                id: "short-ok",
                text: "OK",
                expectedLanguage: nil,
                isClear: false
            ),
            LanguageSample(
                id: "short-han",
                text: "行",
                expectedLanguage: nil,
                isClear: false
            ),
            LanguageSample(
                id: "brand",
                text: "Apple Intelligence",
                expectedLanguage: nil,
                isClear: false
            ),
            LanguageSample(
                id: "numbers",
                text: "2026-08-21 15:30",
                expectedLanguage: nil,
                isClear: false
            )
        ]
    }

    private func evaluateEntities() -> [EntityResult] {
        makeEntitySamples().map { sample in
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sample.text
            tagger.setLanguage(
                sample.language,
                range: sample.text.startIndex..<sample.text.endIndex
            )

            var detected: [EntityMatch] = []
            tagger.enumerateTags(
                in: sample.text.startIndex..<sample.text.endIndex,
                unit: .word,
                scheme: .nameType,
                options: [.omitWhitespace, .omitPunctuation, .joinNames]
            ) { tag, range in
                guard let tag else { return true }
                detected.append(
                    EntityMatch(
                        text: String(sample.text[range]),
                        tag: tag.rawValue
                    )
                )
                return true
            }

            let expected = sample.expected.map {
                EntityMatch(text: $0.text, tag: $0.tag.rawValue)
            }
            let matchedCount = expected.filter { expectation in
                detected.contains { candidate in
                    candidate.tag == expectation.tag
                        && normalized(candidate.text).contains(normalized(expectation.text))
                }
            }.count
            let exactMatchedCount = expected.filter { expectation in
                detected.contains { candidate in
                    candidate.tag == expectation.tag
                        && normalized(candidate.text) == normalized(expectation.text)
                }
            }.count

            return EntityResult(
                id: sample.id,
                text: sample.text,
                expected: expected,
                detected: detected,
                matchedCount: matchedCount,
                exactMatchedCount: exactMatchedCount
            )
        }
    }

    private func makeEntitySamples() -> [EntitySample] {
        [
            EntitySample(
                id: "en-people-org-place",
                text: "Tim Cook will meet Microsoft executives in Seattle.",
                language: .english,
                expected: [
                    EntityExpectation(text: "Tim Cook", tag: .personalName),
                    EntityExpectation(text: "Microsoft", tag: .organizationName),
                    EntityExpectation(text: "Seattle", tag: .placeName)
                ]
            ),
            EntitySample(
                id: "en-business",
                text: "Sarah from Acme Corporation is visiting London next week.",
                language: .english,
                expected: [
                    EntityExpectation(text: "Sarah", tag: .personalName),
                    EntityExpectation(text: "Acme Corporation", tag: .organizationName),
                    EntityExpectation(text: "London", tag: .placeName)
                ]
            ),
            EntitySample(
                id: "zh-people-org-place",
                text: "李雷下周去上海拜访腾讯公司。",
                language: .simplifiedChinese,
                expected: [
                    EntityExpectation(text: "李雷", tag: .personalName),
                    EntityExpectation(text: "上海", tag: .placeName),
                    EntityExpectation(text: "腾讯公司", tag: .organizationName)
                ]
            ),
            EntitySample(
                id: "zh-business",
                text: "王芳将在深圳与华为团队讨论新项目。",
                language: .simplifiedChinese,
                expected: [
                    EntityExpectation(text: "王芳", tag: .personalName),
                    EntityExpectation(text: "深圳", tag: .placeName),
                    EntityExpectation(text: "华为", tag: .organizationName)
                ]
            )
        ]
    }

    private func makeDataDetector() throws -> NSDataDetector {
        let types: NSTextCheckingResult.CheckingType = [
            .link,
            .phoneNumber,
            .date,
            .address
        ]
        return try NSDataDetector(types: types.rawValue)
    }

    private func evaluateDataDetection(
        using detector: NSDataDetector
    ) -> [DetectorResult] {
        makeDetectorSamples().map { sample in
            let range = NSRange(sample.text.startIndex..., in: sample.text)
            let detected = detector.matches(
                in: sample.text,
                options: [],
                range: range
            ).compactMap { match -> DetectorMatch? in
                guard let swiftRange = Range(match.range, in: sample.text),
                      let type = detectorTypeName(match.resultType) else {
                    return nil
                }
                return DetectorMatch(
                    type: type,
                    text: String(sample.text[swiftRange])
                )
            }
            let detectedTypes = Set(detected.map(\.type))
            return DetectorResult(
                id: sample.id,
                text: sample.text,
                expectedTypes: sample.expectedTypes.sorted(),
                detected: detected,
                matchedTypes: sample.expectedTypes
                    .intersection(detectedTypes)
                    .sorted()
            )
        }
    }

    private func makeDetectorSamples() -> [DetectorSample] {
        [
            DetectorSample(
                id: "en-url-phone",
                text: "See https://www.apple.com and call +1 408-996-1010.",
                expectedTypes: ["link", "phone"]
            ),
            DetectorSample(
                id: "en-date",
                text: "Let's meet on August 28, 2026 at 3:00 PM.",
                expectedTypes: ["date"]
            ),
            DetectorSample(
                id: "en-address",
                text: "Please navigate to 1 Apple Park Way, Cupertino, CA 95014.",
                expectedTypes: ["address"]
            ),
            DetectorSample(
                id: "zh-url-phone",
                text: "详情见 https://www.apple.com.cn，联系电话 400-666-8800。",
                expectedTypes: ["link", "phone"]
            ),
            DetectorSample(
                id: "zh-date",
                text: "会议安排在2026年8月28日下午3点。",
                expectedTypes: ["date"]
            ),
            DetectorSample(
                id: "zh-address",
                text: "请导航到深圳市南山区科技园科苑路15号。",
                expectedTypes: ["address"]
            )
        ]
    }

    private func detectorTypeName(
        _ type: NSTextCheckingResult.CheckingType
    ) -> String? {
        switch type {
        case .link:
            return "link"
        case .phoneNumber:
            return "phone"
        case .date:
            return "date"
        case .address:
            return "address"
        default:
            return nil
        }
    }

    private func evaluateSemantics(
        _ corpus: SemanticCorpus
    ) -> SemanticLanguageReport {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: corpus.language) else {
            return SemanticLanguageReport(
                language: corpus.languageID,
                embeddingAvailable: false,
                dimension: nil,
                revision: nil,
                controlAccuracy: nil,
                topOneAccuracy: nil,
                topThreeAccuracy: nil,
                regularTopOneAccuracy: nil,
                adversarialTopOneAccuracy: nil,
                controls: [],
                results: []
            )
        }

        let anchorVectors = corpus.anchors.map { anchor in
            (
                skillID: anchor.skillID,
                vectors: anchor.examples.compactMap(embedding.vector(for:))
            )
        }
        let results = corpus.samples.map { sample in
            let sampleVector = embedding.vector(for: sample.text)
            let distances = anchorVectors.map { anchor in
                let distance = sampleVector.map { vector in
                    anchor.vectors
                        .map { cosineDistance(vector, $0) }
                        .min() ?? 2
                } ?? 2
                return SkillDistance(
                    skillID: anchor.skillID,
                    distance: rounded(distance)
                )
            }.sorted { $0.distance < $1.distance }
            let predicted = distances.first?.skillID
            let topThree = Array(distances.prefix(3))
            return SemanticResult(
                id: sample.id,
                text: sample.text,
                expectedSkillID: sample.expectedSkillID,
                predictedSkillID: predicted,
                topThree: topThree,
                topOneCorrect: predicted == sample.expectedSkillID,
                topThreeCorrect: topThree.contains {
                    $0.skillID == sample.expectedSkillID
                },
                isAdversarial: sample.isAdversarial
            )
        }

        let controls = semanticControls(for: corpus.language).map { control in
            let query = embedding.vector(for: control.query)
            let related = embedding.vector(for: control.related)
            let unrelated = embedding.vector(for: control.unrelated)
            let relatedDistance = pairwiseDistance(query, related)
            let unrelatedDistance = pairwiseDistance(query, unrelated)
            let passed: Bool
            if let relatedDistance, let unrelatedDistance {
                passed = relatedDistance < unrelatedDistance
            } else {
                passed = false
            }
            return SemanticControlResult(
                id: control.id,
                relatedDistance: relatedDistance.map(rounded),
                unrelatedDistance: unrelatedDistance.map(rounded),
                passed: passed
            )
        }
        let regular = results.filter { !$0.isAdversarial }
        let adversarial = results.filter(\.isAdversarial)
        return SemanticLanguageReport(
            language: corpus.languageID,
            embeddingAvailable: true,
            dimension: embedding.dimension,
            revision: embedding.revision,
            controlAccuracy: accuracy(controls, keyPath: \.passed),
            topOneAccuracy: accuracy(results, keyPath: \.topOneCorrect),
            topThreeAccuracy: accuracy(results, keyPath: \.topThreeCorrect),
            regularTopOneAccuracy: accuracy(regular, keyPath: \.topOneCorrect),
            adversarialTopOneAccuracy: accuracy(adversarial, keyPath: \.topOneCorrect),
            controls: controls,
            results: results
        )
    }

    private func semanticControls(for language: NLLanguage) -> [SemanticControl] {
        if language == .simplifiedChinese {
            return [
                SemanticControl(
                    id: "zh-meeting-paraphrase",
                    query: "明天下午三点开会",
                    related: "会议安排在明天下午三点",
                    unrelated: "这个苹果吃起来很甜"
                ),
                SemanticControl(
                    id: "zh-business-paraphrase",
                    query: "请确认报价和交付日期",
                    related: "麻烦核实价格以及什么时候可以交货",
                    unrelated: "周末我准备去公园跑步"
                ),
                SemanticControl(
                    id: "zh-navigation-paraphrase",
                    query: "导航到深圳南山区科苑路",
                    related: "带我去南山区科苑路",
                    unrelated: "总结这份季度报告"
                )
            ]
        }
        return [
            SemanticControl(
                id: "en-meeting-paraphrase",
                query: "The meeting starts tomorrow at 3 PM.",
                related: "We are scheduled to meet at three tomorrow afternoon.",
                unrelated: "This apple tastes very sweet."
            ),
            SemanticControl(
                id: "en-business-paraphrase",
                query: "Please confirm the price and delivery date.",
                related: "Could you verify the quotation and when it will arrive?",
                unrelated: "I plan to run in the park this weekend."
            ),
            SemanticControl(
                id: "en-navigation-paraphrase",
                query: "Navigate to Apple Park in Cupertino.",
                related: "Take me to the Apple Park campus.",
                unrelated: "Summarize the quarterly report."
            )
        ]
    }

    private func makeSemanticCorpora() -> [SemanticCorpus] {
        [
            SemanticCorpus(
                language: .english,
                languageID: "en",
                anchors: englishAnchors,
                samples: englishSemanticSamples
            ),
            SemanticCorpus(
                language: .simplifiedChinese,
                languageID: "zh-Hans",
                anchors: chineseAnchors,
                samples: chineseSemanticSamples
            )
        ]
    }

    private var englishAnchors: [SemanticAnchor] {
        [
            SemanticAnchor(
                skillID: "reply",
                examples: [
                    "A personal message asks me a direct question and expects an answer.",
                    "Someone is waiting for my response in a conversation."
                ]
            ),
            SemanticAnchor(
                skillID: "summarize",
                examples: [
                    "A long article explains a topic with many facts and details.",
                    "A lengthy document needs its main points condensed."
                ]
            ),
            SemanticAnchor(
                skillID: "extractEvents",
                examples: [
                    "An event invitation contains a date, time, and meeting place.",
                    "A scheduled meeting should be added to a calendar."
                ]
            ),
            SemanticAnchor(
                skillID: "extractTodos",
                examples: [
                    "A checklist contains several tasks that need to be completed.",
                    "These action items should be turned into a to-do list."
                ]
            ),
            SemanticAnchor(
                skillID: "navigate",
                examples: [
                    "A street address describes a physical destination.",
                    "This location should be opened for navigation."
                ]
            ),
            SemanticAnchor(
                skillID: "businessReply",
                examples: [
                    "A formal business email requires a professional response.",
                    "A client is discussing a proposal, price, contract, or deadline."
                ]
            )
        ]
    }

    private var chineseAnchors: [SemanticAnchor] {
        [
            SemanticAnchor(
                skillID: "reply",
                examples: [
                    "一条私人消息正在直接询问我，并等待我的回答。",
                    "对方在聊天中提出问题，需要我回复。"
                ]
            ),
            SemanticAnchor(
                skillID: "summarize",
                examples: [
                    "一篇很长的文章包含大量事实、解释和细节。",
                    "一份长文档需要提炼重点并缩短篇幅。"
                ]
            ),
            SemanticAnchor(
                skillID: "extractEvents",
                examples: [
                    "活动邀请中包含日期、时间和开会地点。",
                    "一项已经安排的会议需要加入日历。"
                ]
            ),
            SemanticAnchor(
                skillID: "extractTodos",
                examples: [
                    "清单中包含多项需要完成的任务。",
                    "这些行动项需要整理成待办事项。"
                ]
            ),
            SemanticAnchor(
                skillID: "navigate",
                examples: [
                    "这是一处可以导航前往的街道地址。",
                    "文本描述了一个具体地点和目的地。"
                ]
            ),
            SemanticAnchor(
                skillID: "businessReply",
                examples: [
                    "正式商务邮件需要专业回复。",
                    "客户正在讨论报价、合同、交付时间或合作方案。"
                ]
            )
        ]
    }

    private var englishSemanticSamples: [SemanticSample] {
        [
            SemanticSample(
                id: "en-reply",
                text: "Are you free for a quick call after lunch?",
                expectedSkillID: "reply",
                isAdversarial: false
            ),
            SemanticSample(
                id: "en-summary",
                text: """
                The report reviews renewable energy adoption across twelve regions.
                It compares installation costs, grid capacity, policy incentives,
                and five-year demand forecasts before outlining three scenarios.
                """,
                expectedSkillID: "summarize",
                isAdversarial: false
            ),
            SemanticSample(
                id: "en-event",
                text: "Design review is Friday, August 28 at 3 PM in Meeting Room 5.",
                expectedSkillID: "extractEvents",
                isAdversarial: false
            ),
            SemanticSample(
                id: "en-todos",
                text: "Update the deck\nEmail the client\nBook the meeting room",
                expectedSkillID: "extractTodos",
                isAdversarial: false
            ),
            SemanticSample(
                id: "en-navigation",
                text: "1 Apple Park Way, Cupertino, CA 95014",
                expectedSkillID: "navigate",
                isAdversarial: false
            ),
            SemanticSample(
                id: "en-business",
                text: "Could you revise the quotation and confirm the delivery deadline?",
                expectedSkillID: "businessReply",
                isAdversarial: false
            ),
            SemanticSample(
                id: "en-keyword-trap",
                text: "Can you summarize the contract and send me your answer?",
                expectedSkillID: "reply",
                isAdversarial: true
            ),
            SemanticSample(
                id: "en-date-in-article",
                text: "The article says the company was founded on August 28, 1976.",
                expectedSkillID: "summarize",
                isAdversarial: true
            ),
            SemanticSample(
                id: "en-address-in-question",
                text: "Is 1 Apple Park Way still your billing address?",
                expectedSkillID: "reply",
                isAdversarial: true
            )
        ]
    }

    private var chineseSemanticSamples: [SemanticSample] {
        [
            SemanticSample(
                id: "zh-reply",
                text: "你今天下班以后有时间聊一下吗？",
                expectedSkillID: "reply",
                isAdversarial: false
            ),
            SemanticSample(
                id: "zh-summary",
                text: """
                这份报告比较了十二个地区的可再生能源应用情况，分析了安装成本、
                电网容量、政策激励与未来五年的需求预测，最后提出了三种发展情景。
                """,
                expectedSkillID: "summarize",
                isAdversarial: false
            ),
            SemanticSample(
                id: "zh-event",
                text: "设计评审定在8月28日星期五下午3点，地点是五号会议室。",
                expectedSkillID: "extractEvents",
                isAdversarial: false
            ),
            SemanticSample(
                id: "zh-todos",
                text: "更新演示文稿\n给客户发邮件\n预订会议室",
                expectedSkillID: "extractTodos",
                isAdversarial: false
            ),
            SemanticSample(
                id: "zh-navigation",
                text: "深圳市南山区科技园科苑路15号",
                expectedSkillID: "navigate",
                isAdversarial: false
            ),
            SemanticSample(
                id: "zh-business",
                text: "请更新报价，并确认最终交付时间和付款条件。",
                expectedSkillID: "businessReply",
                isAdversarial: false
            ),
            SemanticSample(
                id: "zh-keyword-trap",
                text: "你能先总结一下合同，再告诉我你的意见吗？",
                expectedSkillID: "reply",
                isAdversarial: true
            ),
            SemanticSample(
                id: "zh-date-in-article",
                text: "文章提到这家公司成立于1976年8月28日。",
                expectedSkillID: "summarize",
                isAdversarial: true
            ),
            SemanticSample(
                id: "zh-address-in-question",
                text: "科苑路15号还是你们现在的账单地址吗？",
                expectedSkillID: "reply",
                isAdversarial: true
            )
        ]
    }

    private func benchmark(
        detector: NSDataDetector,
        semanticCorpora: [SemanticCorpus]
    ) -> [LatencyReport] {
        let iterations = 50
        let languageText = "请确认明天下午的会议时间，并把更新后的方案发给客户。"
        let detectorText = "Meeting: August 28, 2026 at 3 PM, https://example.com"
        var reports = [
            latencyReport(
                operation: "language-recognition",
                iterations: iterations
            ) {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(languageText)
                _ = recognizer.languageHypotheses(withMaximum: 3)
            },
            latencyReport(
                operation: "data-detection",
                iterations: iterations
            ) {
                _ = detector.matches(
                    in: detectorText,
                    options: [],
                    range: NSRange(detectorText.startIndex..., in: detectorText)
                )
            }
        ]

        if let english = semanticCorpora.first,
           let embedding = NLEmbedding.sentenceEmbedding(for: english.language) {
            let anchorVectors = english.anchors.flatMap(\.examples)
                .compactMap(embedding.vector(for:))
            reports.append(
                latencyReport(
                    operation: "semantic-routing-precomputed-anchors",
                    iterations: iterations
                ) {
                    guard let vector = embedding.vector(
                        for: "Can you call me after lunch?"
                    ) else {
                        return
                    }
                    _ = anchorVectors.map { cosineDistance(vector, $0) }.min()
                }
            )
        }
        return reports
    }

    private func latencyReport(
        operation: String,
        iterations: Int,
        body: () -> Void
    ) -> LatencyReport {
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations {
            body()
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        return LatencyReport(
            operation: operation,
            iterations: iterations,
            averageMilliseconds: rounded(elapsed * 1_000 / Double(iterations))
        )
    }

    private func accuracy<T>(
        _ values: [T],
        keyPath: KeyPath<T, Bool>
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        return ratio(
            numerator: values.filter { $0[keyPath: keyPath] }.count,
            denominator: values.count
        )
    }

    private func ratio(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return rounded(Double(numerator) / Double(denominator))
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    private func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }

    private func pairwiseDistance(
        _ first: [Double]?,
        _ second: [Double]?
    ) -> Double? {
        guard let first, let second else { return nil }
        return cosineDistance(first, second)
    }

    private func cosineDistance(_ first: [Double], _ second: [Double]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 2 }
        var dotProduct = 0.0
        var firstMagnitude = 0.0
        var secondMagnitude = 0.0
        for index in first.indices {
            dotProduct += first[index] * second[index]
            firstMagnitude += first[index] * first[index]
            secondMagnitude += second[index] * second[index]
        }
        guard firstMagnitude > 0, secondMagnitude > 0 else { return 2 }
        return 1 - dotProduct / (firstMagnitude.squareRoot() * secondMagnitude.squareRoot())
    }
}
