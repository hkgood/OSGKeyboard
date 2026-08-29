// ClipboardSemanticAnalyzer.swift
// OSGKeyboard · Shared
//
// Fully local clipboard labeling. Deterministic Apple detectors produce
// structural facts; project-trained NLModel classifiers add conservative
// sentence-level intent labels. No clipboard text leaves the device here.

import Foundation
import NaturalLanguage

public struct ClipboardLanguageLabel: Equatable, Sendable {
    public let identifier: String
    public let confidence: Double
}

public struct ClipboardDateLabel: Equatable, Sendable {
    public let sourceText: String
    public let date: Date
    public let duration: TimeInterval
    public let timeZoneIdentifier: String?
}

public struct ClipboardTextLabel: Equatable, Sendable {
    public let sourceText: String
}

public enum ClipboardSentimentLabel: String, Equatable, Sendable {
    case positive
    case neutral
    case negative
    case unknown
}

public struct ClipboardIntentLabel: Equatable, Sendable {
    public let confidence: Double
    public let threshold: Double
    public let isDetected: Bool
    public let isApprovedForAutomaticRouting: Bool
}

public enum ClipboardSemanticDomain: String, CaseIterable, Equatable, Sendable {
    case finance
    case travel
    case calendar
    case communication
    case media
    case smartHome
    case shopping
    case dining
    case health
    case weather
    case accountService
    case generalKnowledge

    public var localizationKey: String {
        "keyboard.semantic.domain.\(rawValue)"
    }
}

public struct ClipboardVerifierDecision: Equatable, Sendable {
    public let group: String
    public let label: String
    public let confidence: Double
    public let margin: Double
    public let isShadow: Bool
    public let isRouted: Bool
}

public struct ClipboardSemanticAnalysis: Equatable, Sendable {
    public let language: ClipboardLanguageLabel?
    public let dates: [ClipboardDateLabel]
    public let addresses: [ClipboardTextLabel]
    public let phoneNumbers: [ClipboardTextLabel]
    public let urls: [URL]
    public let personNames: [ClipboardTextLabel]
    public let organizationNames: [ClipboardTextLabel]
    public let sentiment: ClipboardSentimentLabel
    public let sentimentConfidence: Double
    public let task: ClipboardIntentLabel
    public let question: ClipboardIntentLabel
    public let invitation: ClipboardIntentLabel
    public let complaint: ClipboardIntentLabel
    public let replyableMessage: ClipboardIntentLabel
    public let scheduleNegotiation: ClipboardIntentLabel
    public let confirmationDecision: ClipboardIntentLabel
    public let followUpReminder: ClipboardIntentLabel
    public let blessing: ClipboardIntentLabel
    public let actionVerifier: ClipboardVerifierDecision?
    public let coordinationVerifier: ClipboardVerifierDecision?
    public let assistantCommand: ClipboardIntentLabel
    public let informationQuery: ClipboardIntentLabel
    public let systemNotification: ClipboardIntentLabel
    public let domain: ClipboardSemanticDomain?
    public let domainConfidence: Double?

    public var hasDateOrTime: Bool { !dates.isEmpty }
    public var hasAddress: Bool { !addresses.isEmpty }
    public var hasPhoneNumber: Bool { !phoneNumbers.isEmpty }
    public var singlePhoneNumber: String? {
        AIPhoneNumberResolver.singlePhoneNumber(from: phoneNumbers)
    }
    public var hasURL: Bool { !urls.isEmpty }
    public var singleWebURL: URL? {
        ClipboardWebLinkResolver.singleWebURL(from: urls)
    }
    public var hasPersonName: Bool { !personNames.isEmpty }
    public var hasOrganizationName: Bool { !organizationNames.isEmpty }

    public init(
        language: ClipboardLanguageLabel?,
        dates: [ClipboardDateLabel],
        addresses: [ClipboardTextLabel],
        phoneNumbers: [ClipboardTextLabel],
        urls: [URL],
        personNames: [ClipboardTextLabel],
        organizationNames: [ClipboardTextLabel],
        sentiment: ClipboardSentimentLabel,
        sentimentConfidence: Double,
        task: ClipboardIntentLabel,
        question: ClipboardIntentLabel,
        invitation: ClipboardIntentLabel,
        complaint: ClipboardIntentLabel,
        replyableMessage: ClipboardIntentLabel,
        scheduleNegotiation: ClipboardIntentLabel,
        confirmationDecision: ClipboardIntentLabel,
        followUpReminder: ClipboardIntentLabel,
        blessing: ClipboardIntentLabel,
        actionVerifier: ClipboardVerifierDecision?,
        coordinationVerifier: ClipboardVerifierDecision?,
        assistantCommand: ClipboardIntentLabel = .notDetected,
        informationQuery: ClipboardIntentLabel = .notDetected,
        systemNotification: ClipboardIntentLabel = .notDetected,
        domain: ClipboardSemanticDomain? = nil,
        domainConfidence: Double? = nil
    ) {
        self.language = language
        self.dates = dates
        self.addresses = addresses
        self.phoneNumbers = phoneNumbers
        self.urls = urls
        self.personNames = personNames
        self.organizationNames = organizationNames
        self.sentiment = sentiment
        self.sentimentConfidence = sentimentConfidence
        self.task = task
        self.question = question
        self.invitation = invitation
        self.complaint = complaint
        self.replyableMessage = replyableMessage
        self.scheduleNegotiation = scheduleNegotiation
        self.confirmationDecision = confirmationDecision
        self.followUpReminder = followUpReminder
        self.blessing = blessing
        self.actionVerifier = actionVerifier
        self.coordinationVerifier = coordinationVerifier
        self.assistantCommand = assistantCommand
        self.informationQuery = informationQuery
        self.systemNotification = systemNotification
        self.domain = domain
        self.domainConfidence = domainConfidence
    }
}

public extension ClipboardIntentLabel {
    static let notDetected = ClipboardIntentLabel(
        confidence: 0,
        threshold: 1,
        isDetected: false,
        isApprovedForAutomaticRouting: false
    )
}

/// Deterministic HTTP(S) extraction shared by analysis and direct URL skills.
/// Bare domains are upgraded to HTTPS; explicit HTTP links preserve their scheme.
public enum ClipboardWebLinkResolver: Sendable {
    public static func webURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let urls: [URL] = detector.matches(
            in: text,
            options: [],
            range: range
        ).compactMap { match -> URL? in
            guard let swiftRange = Range(match.range, in: text),
                  let url = match.url else {
                return nil
            }
            return normalizedWebURL(
                url,
                sourceText: String(text[swiftRange])
            )
        }
        return deduplicated(urls)
    }

    public static func singleWebURL(in text: String) -> URL? {
        singleWebURL(from: webURLs(in: text))
    }

    public static func singleWebURL(from urls: [URL]) -> URL? {
        let webURLs = deduplicated(urls.compactMap {
            normalizedWebURL($0, sourceText: $0.absoluteString)
        })
        return webURLs.count == 1 ? webURLs[0] : nil
    }

    static func normalizedWebURL(_ url: URL, sourceText: String) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let source = sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scheme = components.scheme?.lowercased()
        guard scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }
        if scheme == "http",
           !source.hasPrefix("http://"),
           !source.contains("://") {
            components.scheme = "https"
        }
        return components.url
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter {
            seen.insert($0.absoluteString).inserted
        }
    }
}

public actor ClipboardSemanticAnalyzer {
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let classifiers: [ManifestClassifier]
        let verifiers: [ManifestVerifier]?
    }

    private struct ManifestClassifier: Decodable {
        let id: String
        let modelFile: String
        let positiveLabel: String?
        let confidenceThreshold: Double?
        let confidenceThresholdsByLanguage: [String: Double]?
        let acceptedForAutomaticRouting: Bool
    }

    private struct ManifestVerifier: Decodable {
        let id: String
        let modelFile: String
        let confidenceThreshold: Double
        let confidenceThresholdsByLanguage: [String: Double]?
        let minimumMargin: Double
        let minimumMarginsByLanguage: [String: Double]?
        let acceptedForAutomaticRouting: Bool
        let deploymentMode: String
    }

    private struct ModelEntry {
        let configuration: ManifestClassifier
        let model: NLModel
    }

    private struct VerifierEntry {
        let configuration: ManifestVerifier
        let model: NLModel
    }

    private enum IntentID: String, CaseIterable {
        case task
        case question
        case invitation
        case complaint
        case replyableMessage
        case scheduleNegotiation
        case confirmationDecision
        case followUpReminder
        case blessing
        case assistantCommand
        case informationQuery
        case systemNotification

        var isDisplayOnly: Bool {
            switch self {
            case .assistantCommand, .informationQuery, .systemNotification:
                return true
            case .task, .question, .invitation, .complaint,
                 .replyableMessage, .scheduleNegotiation,
                 .confirmationDecision, .followUpReminder, .blessing:
                return false
            }
        }
    }

    private static let resourceDirectory = "ClipboardSemantics"
    private static let manifestName = "clipboard-semantic-models"
    private static let maximumSemanticSegments = 8
    private static let maximumSegmentCharacters = 500
    private static let minimumSentimentConfidence = 0.65
    private static let minimumSentimentMargin = 0.15

    private let bundles: [Bundle]
    private var manifest: Manifest?
    private var models: [String: ModelEntry] = [:]
    private var verifierModels: [String: VerifierEntry] = [:]
    private var didAttemptManifestLoad = false

    public init(additionalBundles: [Bundle] = []) {
        var resolved = additionalBundles
        resolved.append(Bundle(for: BundleToken.self))
        resolved.append(.main)
        var seen = Set<String>()
        bundles = resolved.filter { seen.insert($0.bundlePath).inserted }
    }

    public func analyze(_ sourceText: String) -> ClipboardSemanticAnalysis {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return emptyAnalysis()
        }

        let language = languageLabel(for: text)
        let detectedData = detectStructuredData(in: text)
        let entities = detectNames(
            in: text,
            language: language.flatMap { NLLanguage(rawValue: $0.identifier) }
        )
        let segments = semanticSegments(in: text)
        let languageIdentifier = language?.identifier
        let taskCandidate = intentLabel(
            .task,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let questionCandidate = intentLabel(
            .question,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let invitationCandidate = intentLabel(
            .invitation,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let complaint = intentLabel(
            .complaint,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let task = adjustedTaskLabel(
            taskCandidate,
            complaint: complaint,
            text: text
        )
        let replyableMessage = intentLabel(
            .replyableMessage,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let scheduleNegotiationCandidate = intentLabel(
            .scheduleNegotiation,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let confirmationDecisionCandidate = intentLabel(
            .confirmationDecision,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let followUpReminderCandidate = intentLabel(
            .followUpReminder,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let blessingCandidate = intentLabel(
            .blessing,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let assistantCommand = intentLabel(
            .assistantCommand,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let informationQuery = intentLabel(
            .informationQuery,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let systemNotification = intentLabel(
            .systemNotification,
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let domain = domainLabel(
            segments: segments,
            languageIdentifier: languageIdentifier
        )
        let blessing = Self.adjustedBlessingLabel(blessingCandidate, text: text)
        let sentiment = sentimentLabel(segments: segments)
        let actionVerifier = verifierDecision(
            id: "action",
            segments: segments,
            languageIdentifier: languageIdentifier,
            shouldEvaluate: shouldEvaluateActionVerifier(
                task: task,
                question: questionCandidate,
                complaint: complaint
            )
        )
        let coordinationVerifier = verifierDecision(
            id: "coordination",
            segments: segments,
            languageIdentifier: languageIdentifier,
            shouldEvaluate: shouldEvaluateCoordinationVerifier(
                invitation: invitationCandidate,
                scheduleNegotiation: scheduleNegotiationCandidate,
                confirmationDecision: confirmationDecisionCandidate,
                followUpReminder: followUpReminderCandidate
            )
        )
        let verifiedAction = verifiedActionLabels(
            task: task,
            question: questionCandidate,
            complaint: complaint,
            decision: actionVerifier
        )
        let verifiedCoordination = verifiedCoordinationLabels(
            invitation: invitationCandidate,
            scheduleNegotiation: scheduleNegotiationCandidate,
            confirmationDecision: confirmationDecisionCandidate,
            followUpReminder: followUpReminderCandidate,
            decision: coordinationVerifier
        )

        return ClipboardSemanticAnalysis(
            language: language,
            dates: detectedData.dates,
            addresses: detectedData.addresses,
            phoneNumbers: detectedData.phoneNumbers,
            urls: detectedData.urls,
            personNames: entities.people,
            organizationNames: entities.organizations,
            sentiment: sentiment.label,
            sentimentConfidence: sentiment.confidence,
            task: verifiedAction.task,
            question: verifiedAction.question,
            invitation: verifiedCoordination.invitation,
            complaint: verifiedAction.complaint,
            replyableMessage: replyableMessage,
            scheduleNegotiation: verifiedCoordination.scheduleNegotiation,
            confirmationDecision: verifiedCoordination.confirmationDecision,
            followUpReminder: verifiedCoordination.followUpReminder,
            blessing: blessing,
            actionVerifier: actionVerifier,
            coordinationVerifier: coordinationVerifier,
            assistantCommand: assistantCommand,
            informationQuery: informationQuery,
            systemNotification: systemNotification,
            domain: domain.value,
            domainConfidence: domain.confidence
        )
    }

    private func shouldEvaluateActionVerifier(
        task: ClipboardIntentLabel,
        question: ClipboardIntentLabel,
        complaint: ClipboardIntentLabel
    ) -> Bool {
        [task, question, complaint].contains {
            $0.confidence >= min($0.threshold, 0.50)
        }
    }

    private func shouldEvaluateCoordinationVerifier(
        invitation: ClipboardIntentLabel,
        scheduleNegotiation: ClipboardIntentLabel,
        confirmationDecision: ClipboardIntentLabel,
        followUpReminder: ClipboardIntentLabel
    ) -> Bool {
        [
            invitation,
            scheduleNegotiation,
            confirmationDecision,
            followUpReminder
        ].contains {
            $0.confidence >= min($0.threshold, 0.50)
        }
    }

    private func verifiedActionLabels(
        task: ClipboardIntentLabel,
        question: ClipboardIntentLabel,
        complaint: ClipboardIntentLabel,
        decision: ClipboardVerifierDecision?
    ) -> (
        task: ClipboardIntentLabel,
        question: ClipboardIntentLabel,
        complaint: ClipboardIntentLabel
    ) {
        guard let configuration = verifierConfiguration(id: "action") else {
            return (task, question, complaint)
        }
        guard configuration.acceptedForAutomaticRouting,
              configuration.deploymentMode == "automatic" else {
            return (task, question, complaint)
        }
        guard let decision else {
            return (
                routedLabel(task, isApproved: false),
                routedLabel(question, isApproved: false),
                routedLabel(complaint, isApproved: false)
            )
        }
        let taskApproved = decision.isRouted
            && ["taskOnly", "both"].contains(decision.label)
        let questionApproved = decision.isRouted
            && decision.label == "questionRequest"
        let complaintApproved = decision.isRouted
            && ["complaintOnly", "both"].contains(decision.label)
        return (
            routedLabel(task, isApproved: taskApproved),
            routedLabel(question, isApproved: questionApproved),
            routedLabel(complaint, isApproved: complaintApproved)
        )
    }

    private func verifiedCoordinationLabels(
        invitation: ClipboardIntentLabel,
        scheduleNegotiation: ClipboardIntentLabel,
        confirmationDecision: ClipboardIntentLabel,
        followUpReminder: ClipboardIntentLabel,
        decision: ClipboardVerifierDecision?
    ) -> (
        invitation: ClipboardIntentLabel,
        scheduleNegotiation: ClipboardIntentLabel,
        confirmationDecision: ClipboardIntentLabel,
        followUpReminder: ClipboardIntentLabel
    ) {
        guard let configuration = verifierConfiguration(id: "coordination") else {
            return (
                invitation,
                scheduleNegotiation,
                confirmationDecision,
                followUpReminder
            )
        }
        guard configuration.acceptedForAutomaticRouting,
              configuration.deploymentMode == "automatic" else {
            return (
                invitation,
                scheduleNegotiation,
                confirmationDecision,
                followUpReminder
            )
        }
        guard let decision else {
            return (
                routedLabel(invitation, isApproved: false),
                routedLabel(scheduleNegotiation, isApproved: false),
                routedLabel(confirmationDecision, isApproved: false),
                routedLabel(followUpReminder, isApproved: false)
            )
        }
        return (
            routedLabel(
                invitation,
                isApproved: decision.isRouted && decision.label == "invitation"
            ),
            routedLabel(
                scheduleNegotiation,
                isApproved: decision.isRouted
                    && decision.label == "scheduleNegotiation"
            ),
            routedLabel(
                confirmationDecision,
                isApproved: decision.isRouted
                    && decision.label == "confirmationDecision"
            ),
            routedLabel(
                followUpReminder,
                isApproved: decision.isRouted
                    && decision.label == "followUpReminder"
            )
        )
    }

    private func routedLabel(
        _ candidate: ClipboardIntentLabel,
        isApproved: Bool
    ) -> ClipboardIntentLabel {
        ClipboardIntentLabel(
            confidence: candidate.confidence,
            threshold: candidate.threshold,
            isDetected: isApproved,
            isApprovedForAutomaticRouting: isApproved
        )
    }

    private func adjustedTaskLabel(
        _ task: ClipboardIntentLabel,
        complaint: ClipboardIntentLabel,
        text: String
    ) -> ClipboardIntentLabel {
        guard task.isDetected,
              Self.shouldSuppressTask(
                text: text,
                complaintConfidence: complaint.confidence
              ) else {
            return task
        }
        return ClipboardIntentLabel(
            confidence: task.confidence,
            threshold: task.threshold,
            isDetected: false,
            isApprovedForAutomaticRouting: task.isApprovedForAutomaticRouting
        )
    }

    static func shouldSuppressTask(
        text: String,
        complaintConfidence: Double
    ) -> Bool {
        guard complaintConfidence >= 0.60 else { return false }
        let normalized = text.lowercased()
        let explicitTaskMarkers = [
            "请", "麻烦", "能否", "可以请你", "由你", "交给你", "需要你",
            "你负责", "下一步", "行动项", "please ", "can you", "could you",
            "would you", "assigned to you", "you are responsible", "we need you",
            "would like you", "counting on you", "take ownership", "your task",
            "next action", "complete the", "finish the", "send it to",
            "deliver it to"
        ]
        return !explicitTaskMarkers.contains { normalized.contains($0) }
    }

    static func adjustedBlessingLabel(
        _ candidate: ClipboardIntentLabel,
        text: String
    ) -> ClipboardIntentLabel {
        if isRejectedBlessingContext(in: text) {
            return ClipboardIntentLabel(
                confidence: candidate.confidence,
                threshold: 1,
                isDetected: false,
                isApprovedForAutomaticRouting: candidate.isApprovedForAutomaticRouting
            )
        }

        if hasExplicitBlessingMarker(in: text) {
            // Explicit blessing phrases are deterministic routing evidence.
            return ClipboardIntentLabel(
                confidence: 1,
                threshold: 1,
                isDetected: true,
                isApprovedForAutomaticRouting: true
            )
        }

        let modelThreshold = max(candidate.threshold, 0.98)
        let isModelApproved = candidate.isApprovedForAutomaticRouting
            && candidate.confidence >= modelThreshold
        return ClipboardIntentLabel(
            confidence: candidate.confidence,
            threshold: modelThreshold,
            isDetected: isModelApproved,
            isApprovedForAutomaticRouting: candidate.isApprovedForAutomaticRouting
        )
    }

    static func hasExplicitBlessingMarker(in text: String) -> Bool {
        let normalized = normalizedBlessingText(text)
        guard !isRejectedBlessingContext(in: normalized) else {
            return false
        }
        let markers = [
            "生日快乐", "新年快乐", "春节快乐", "元旦快乐", "元宵节快乐",
            "端午安康", "端午快乐", "节日快乐", "圣诞快乐", "中秋快乐",
            "国庆快乐", "新婚快乐", "毕业快乐", "纪念日快乐", "恭喜",
            "祝贺", "预祝", "祝你", "祝您", "祝大家", "祝各位", "祝我们",
            "祝他", "祝她", "祝他们", "祝愿", "愿你", "愿您", "愿大家",
            "愿各位", "愿我们", "愿他", "愿她", "愿他们", "一路顺风",
            "一路平安", "早日康复", "前程似锦", "万事如意", "心想事成",
            "平安喜乐", "节哀顺变", "开业大吉", "做个好梦",
            "happy birthday", "happy new year", "happy anniversary",
            "happy graduation", "happy wedding", "merry christmas",
            "happy holidays", "congratulations", "congrats", "best wishes",
            "good luck", "safe travels", "get well soon", "sweet dreams",
            "all the best", "wishing you", "wishing him", "wishing her",
            "wishing them", "wish you", "wish him", "wish her", "wish them",
            "let us wish", "let's wish", "we wish", "may you", "may your",
            "hope you have"
        ]
        return markers.contains { normalized.contains($0) }
    }

    static func isRejectedBlessingContext(in text: String) -> Bool {
        let normalized = normalizedBlessingText(text)
        let blockedFragments = [
            "祝福模板", "祝福语模板", "祝福文案", "文章引用", "搜索词",
            "系统正在检查", "文档里收录", "文档里引用", "海报上印着",
            "示例文本", "关键词列表", "分析句式", "贺卡名单", "收集祝福",
            "如何描述生日快乐", "怎么说生日快乐", "如何写生日祝福",
            "怎么写生日祝福", "帮我写一段祝福", "帮我生成祝福",
            "greeting template", "message template", "blessing template",
            "the article quotes", "the document quotes", "search phrase",
            "system is checking", "document contains", "card list",
            "quotes the phrase", "sample text", "keyword list",
            "how would you describe a happy birthday",
            "how do you say happy birthday", "how to write a birthday wish",
            "what does happy birthday mean", "write a birthday wish",
            "宁愿你", "祝你倒闭", "祝你立马倒闭", "祝你去死", "祝你倒霉",
            "祝你失败", "祝你完蛋", "wish you would die", "wish you bad luck"
        ]
        if blockedFragments.contains(where: { normalized.contains($0) }) {
            return true
        }

        let receivedPatterns = [
            #"(?:谢谢|感谢|收到|收到了|多谢).{0,20}(?:祝福|祝愿|生日快乐|恭喜)"#,
            #"(?:thank|thanks).{0,64}(?:wish|wishes|congratulations|birthday message)"#
        ]
        let reportedOrMetaPatterns = [
            #"(?:帮我写|帮我生成|搜索|查找).{0,16}(?:祝福|祝福语|祝愿|生日快乐)"#,
            #"(?:他说|她说|他们说|会议记录|新闻|群公告).{0,20}(?:祝|愿|恭喜)"#,
            #"(?:he said|she said|they said|meeting notes|the article reports).{0,32}(?:wish|congratulat)"#
        ]
        if reportedOrMetaPatterns.contains(where: {
            normalized.range(of: $0, options: .regularExpression) != nil
        }) {
            return true
        }
        let containsReciprocalWish = [
            "也祝", "同样祝", "，祝你", "，祝您", "。祝你", "。祝您",
            ". wish you", ". wishing you", "! wish you", "! wishing you",
            ", and wish you", ", wishing you", "same to you"
        ].contains { normalized.contains($0) }
        if !containsReciprocalWish,
           receivedPatterns.contains(where: {
               normalized.range(of: $0, options: .regularExpression) != nil
           }) {
            return true
        }

        let plainGreetings = [
            "你好", "您好", "早上好", "中午好", "下午好", "晚上好",
            "晚安", "好久不见", "hello", "good morning", "good afternoon",
            "good evening", "long time no see"
        ]
        let trimmed = normalized.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
        if plainGreetings.contains(trimmed) {
            return true
        }

        let celebrationOnly = [
            "庆祝", "庆功", "庆典", "celebrate", "celebration"
        ].contains { normalized.contains($0) }
        return celebrationOnly && !containsDirectWishCue(in: normalized)
    }

    private static func normalizedBlessingText(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
    }

    private static func containsDirectWishCue(in normalized: String) -> Bool {
        [
            "祝你", "祝您", "祝大家", "祝各位", "祝他", "祝她", "祝他们",
            "愿你", "愿您", "愿大家", "愿他", "愿她", "恭喜", "祝贺",
            "wishing you", "wish you", "wish him", "wish her", "wish them",
            "congratulations", "congrats", "good luck", "best wishes"
        ].contains { normalized.contains($0) }
    }

    private func emptyAnalysis() -> ClipboardSemanticAnalysis {
        let emptyIntent = ClipboardIntentLabel.notDetected
        return ClipboardSemanticAnalysis(
            language: nil,
            dates: [],
            addresses: [],
            phoneNumbers: [],
            urls: [],
            personNames: [],
            organizationNames: [],
            sentiment: .unknown,
            sentimentConfidence: 0,
            task: emptyIntent,
            question: emptyIntent,
            invitation: emptyIntent,
            complaint: emptyIntent,
            replyableMessage: emptyIntent,
            scheduleNegotiation: emptyIntent,
            confirmationDecision: emptyIntent,
            followUpReminder: emptyIntent,
            blessing: emptyIntent,
            actionVerifier: nil,
            coordinationVerifier: nil,
            assistantCommand: emptyIntent,
            informationQuery: emptyIntent,
            systemNotification: emptyIntent,
            domain: nil,
            domainConfidence: nil
        )
    }

    private func languageLabel(for text: String) -> ClipboardLanguageLabel? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 3)[dominant] ?? 0
        return ClipboardLanguageLabel(
            identifier: dominant.rawValue,
            confidence: rounded(confidence)
        )
    }

    private func detectStructuredData(
        in text: String
    ) -> (
        dates: [ClipboardDateLabel],
        addresses: [ClipboardTextLabel],
        phoneNumbers: [ClipboardTextLabel],
        urls: [URL]
    ) {
        let checkingTypes: NSTextCheckingResult.CheckingType = [
            .date,
            .address,
            .phoneNumber,
            .link
        ]
        guard let detector = try? NSDataDetector(types: checkingTypes.rawValue) else {
            return ([], [], [], [])
        }
        let range = NSRange(text.startIndex..., in: text)
        var dates: [ClipboardDateLabel] = []
        var addresses: [ClipboardTextLabel] = []
        var phoneNumbers: [ClipboardTextLabel] = []
        var urls: [URL] = []

        for match in detector.matches(in: text, options: [], range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let source = String(text[swiftRange])
            switch match.resultType {
            case .date:
                if let date = match.date {
                    dates.append(
                        ClipboardDateLabel(
                            sourceText: source,
                            date: date,
                            duration: match.duration,
                            timeZoneIdentifier: match.timeZone?.identifier
                        )
                    )
                }
            case .address:
                addresses.append(ClipboardTextLabel(sourceText: source))
            case .phoneNumber:
                phoneNumbers.append(
                    ClipboardTextLabel(sourceText: match.phoneNumber ?? source)
                )
            case .link:
                if let url = match.url,
                   let url = ClipboardWebLinkResolver.normalizedWebURL(
                       url,
                       sourceText: source
                   ) {
                    urls.append(url)
                }
            default:
                continue
            }
        }
        return (
            dates,
            deduplicated(addresses),
            deduplicated(phoneNumbers),
            Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
        )
    }

    private func detectNames(
        in text: String,
        language: NLLanguage?
    ) -> (
        people: [ClipboardTextLabel],
        organizations: [ClipboardTextLabel]
    ) {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        if let language {
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        }
        var people: [ClipboardTextLabel] = []
        var organizations: [ClipboardTextLabel] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            switch tag {
            case .personalName:
                people.append(ClipboardTextLabel(sourceText: String(text[range])))
            case .organizationName:
                organizations.append(ClipboardTextLabel(sourceText: String(text[range])))
            default:
                break
            }
            return true
        }
        return (deduplicated(people), deduplicated(organizations))
    }

    private func semanticSegments(in text: String) -> [String] {
        if text.count <= Self.maximumSegmentCharacters {
            return [text]
        }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var segments: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let segment = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(String(segment.prefix(Self.maximumSegmentCharacters)))
            }
            return segments.count < Self.maximumSemanticSegments
        }
        if segments.isEmpty {
            return [String(text.prefix(Self.maximumSegmentCharacters))]
        }
        return segments
    }

    private func intentLabel(
        _ id: IntentID,
        segments: [String],
        languageIdentifier: String?
    ) -> ClipboardIntentLabel {
        guard let entry = modelEntry(id: id.rawValue),
              let positiveLabel = entry.configuration.positiveLabel else {
            return ClipboardIntentLabel(
                confidence: 0,
                threshold: 1,
                isDetected: false,
                isApprovedForAutomaticRouting: false
            )
        }
        let languageThreshold = languageIdentifier.flatMap {
            entry.configuration.confidenceThresholdsByLanguage?[$0]
        }
        let threshold = languageThreshold
            ?? entry.configuration.confidenceThreshold
            ?? 1
        let confidence = segments.map { segment in
            entry.model.predictedLabelHypotheses(
                for: segment,
                maximumCount: 2
            )[positiveLabel] ?? 0
        }.max() ?? 0
        // Boundary classifiers launch in display/shadow mode. They may expose a
        // threshold-crossing result, but can never authorize an existing route.
        let approved = entry.configuration.acceptedForAutomaticRouting
            && !id.isDisplayOnly
        return ClipboardIntentLabel(
            confidence: rounded(confidence),
            threshold: rounded(threshold),
            isDetected: (approved || id.isDisplayOnly) && confidence >= threshold,
            isApprovedForAutomaticRouting: approved
        )
    }

    private func domainLabel(
        segments: [String],
        languageIdentifier: String?
    ) -> (value: ClipboardSemanticDomain?, confidence: Double?) {
        guard let entry = modelEntry(id: "domain") else {
            return (nil, nil)
        }
        let threshold = languageIdentifier.flatMap {
            entry.configuration.confidenceThresholdsByLanguage?[$0]
        } ?? entry.configuration.confidenceThreshold ?? 1
        let winners = segments.compactMap { segment -> (
            domain: ClipboardSemanticDomain,
            confidence: Double
        )? in
            let ranked = entry.model.predictedLabelHypotheses(
                for: segment,
                maximumCount: ClipboardSemanticDomain.allCases.count
            ).sorted { $0.value > $1.value }
            guard let winner = ranked.first,
                  let domain = ClipboardSemanticDomain(rawValue: winner.key) else {
                return nil
            }
            return (domain, winner.value)
        }
        guard let winner = winners.max(by: {
            $0.confidence < $1.confidence
        }), winner.confidence >= threshold else {
            return (nil, nil)
        }
        return (winner.domain, rounded(winner.confidence))
    }

    private func sentimentLabel(
        segments: [String]
    ) -> (label: ClipboardSentimentLabel, confidence: Double) {
        guard let entry = modelEntry(id: "sentiment") else {
            return (.unknown, 0)
        }
        var totals: [String: Double] = [:]
        for segment in segments {
            for (label, confidence) in entry.model.predictedLabelHypotheses(
                for: segment,
                maximumCount: 3
            ) {
                totals[label, default: 0] += confidence
            }
        }
        let divisor = Double(max(segments.count, 1))
        let ranked = totals
            .map { (label: $0.key, confidence: $0.value / divisor) }
            .sorted { $0.confidence > $1.confidence }
        guard let winner = ranked.first else { return (.unknown, 0) }
        let runnerUp = ranked.dropFirst().first?.confidence ?? 0
        guard entry.configuration.acceptedForAutomaticRouting,
              winner.confidence >= Self.minimumSentimentConfidence,
              winner.confidence - runnerUp >= Self.minimumSentimentMargin,
              let label = ClipboardSentimentLabel(rawValue: winner.label)
        else {
            return (.unknown, rounded(winner.confidence))
        }
        return (label, rounded(winner.confidence))
    }

    private func modelEntry(id: String) -> ModelEntry? {
        if let cached = models[id] {
            return cached
        }
        guard let configuration = loadedManifest()?
            .classifiers
            .first(where: { $0.id == id }),
              let modelURL = modelURL(fileName: configuration.modelFile),
              let model = try? NLModel(contentsOf: modelURL) else {
            return nil
        }
        let entry = ModelEntry(configuration: configuration, model: model)
        models[id] = entry
        return entry
    }

    private func verifierDecision(
        id: String,
        segments: [String],
        languageIdentifier: String?,
        shouldEvaluate: Bool
    ) -> ClipboardVerifierDecision? {
        guard shouldEvaluate,
              let entry = verifierEntry(id: id) else {
            return nil
        }
        let rankedSegments = segments.compactMap { segment -> (
            label: String,
            confidence: Double,
            margin: Double
        )? in
            let ranked = entry.model.predictedLabelHypotheses(
                for: segment,
                maximumCount: 2
            ).sorted { $0.value > $1.value }
            guard let winner = ranked.first else { return nil }
            return (
                winner.key,
                winner.value,
                winner.value - (ranked.dropFirst().first?.value ?? 0)
            )
        }
        guard let winner = rankedSegments.max(by: {
            if $0.confidence != $1.confidence {
                return $0.confidence < $1.confidence
            }
            return $0.margin < $1.margin
        }) else {
            return nil
        }
        let threshold = languageIdentifier.flatMap {
            entry.configuration.confidenceThresholdsByLanguage?[$0]
        } ?? entry.configuration.confidenceThreshold
        let minimumMargin = languageIdentifier.flatMap {
            entry.configuration.minimumMarginsByLanguage?[$0]
        } ?? entry.configuration.minimumMargin
        let isShadow = entry.configuration.deploymentMode == "shadow"
            || !entry.configuration.acceptedForAutomaticRouting
        let isRouted = winner.label != "neither"
            && winner.confidence >= threshold
            && winner.margin >= minimumMargin
        return ClipboardVerifierDecision(
            group: id,
            label: winner.label,
            confidence: rounded(winner.confidence),
            margin: rounded(winner.margin),
            isShadow: isShadow,
            isRouted: isRouted
        )
    }

    private func verifierEntry(id: String) -> VerifierEntry? {
        if let cached = verifierModels[id] {
            return cached
        }
        guard let configuration = loadedManifest()?
            .verifiers?
            .first(where: { $0.id == id }),
              let modelURL = modelURL(fileName: configuration.modelFile),
              let model = try? NLModel(contentsOf: modelURL) else {
            return nil
        }
        let entry = VerifierEntry(configuration: configuration, model: model)
        verifierModels[id] = entry
        return entry
    }

    private func verifierConfiguration(id: String) -> ManifestVerifier? {
        loadedManifest()?.verifiers?.first { $0.id == id }
    }

    private func loadedManifest() -> Manifest? {
        if didAttemptManifestLoad {
            return manifest
        }
        didAttemptManifestLoad = true
        let decoder = JSONDecoder()
        for bundle in bundles {
            let url = bundle.url(
                forResource: Self.manifestName,
                withExtension: "json",
                subdirectory: Self.resourceDirectory
            ) ?? bundle.url(
                forResource: Self.manifestName,
                withExtension: "json"
            )
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let decoded = try? decoder.decode(Manifest.self, from: data),
                  (1...4).contains(decoded.schemaVersion) else {
                continue
            }
            manifest = decoded
            return decoded
        }
        return nil
    }

    private func modelURL(fileName: String) -> URL? {
        let sourceURL = URL(fileURLWithPath: fileName)
        let resource = sourceURL.deletingPathExtension().lastPathComponent
        for bundle in bundles {
            if let url = bundle.url(
                forResource: resource,
                withExtension: "mlmodelc",
                subdirectory: Self.resourceDirectory
            ) ?? bundle.url(
                forResource: resource,
                withExtension: "mlmodelc"
            ) {
                return url
            }
        }
        return nil
    }

    private func deduplicated(
        _ labels: [ClipboardTextLabel]
    ) -> [ClipboardTextLabel] {
        var seen = Set<String>()
        return labels.filter {
            seen.insert($0.sourceText.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )).inserted
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}

private final class BundleToken {}
