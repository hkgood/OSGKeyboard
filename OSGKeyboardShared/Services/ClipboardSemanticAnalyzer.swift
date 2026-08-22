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

    public var hasDateOrTime: Bool { !dates.isEmpty }
    public var hasAddress: Bool { !addresses.isEmpty }
    public var hasPhoneNumber: Bool { !phoneNumbers.isEmpty }
    public var hasURL: Bool { !urls.isEmpty }
    public var hasPersonName: Bool { !personNames.isEmpty }
    public var hasOrganizationName: Bool { !organizationNames.isEmpty }
}

public actor ClipboardSemanticAnalyzer {
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let classifiers: [ManifestClassifier]
    }

    private struct ManifestClassifier: Decodable {
        let id: String
        let modelFile: String
        let positiveLabel: String?
        let confidenceThreshold: Double?
        let acceptedForAutomaticRouting: Bool
    }

    private struct ModelEntry {
        let configuration: ManifestClassifier
        let model: NLModel
    }

    private enum IntentID: String, CaseIterable {
        case task
        case question
        case invitation
        case complaint
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
        let task = intentLabel(.task, segments: segments)
        let question = intentLabel(.question, segments: segments)
        let invitation = intentLabel(.invitation, segments: segments)
        let complaint = intentLabel(.complaint, segments: segments)
        let sentiment = sentimentLabel(segments: segments)

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
            task: task,
            question: question,
            invitation: invitation,
            complaint: complaint
        )
    }

    private func emptyAnalysis() -> ClipboardSemanticAnalysis {
        let emptyIntent = ClipboardIntentLabel(
            confidence: 0,
            threshold: 1,
            isDetected: false,
            isApprovedForAutomaticRouting: false
        )
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
            complaint: emptyIntent
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
                if let url = match.url {
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
        segments: [String]
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
        let threshold = entry.configuration.confidenceThreshold ?? 1
        let confidence = segments.map { segment in
            entry.model.predictedLabelHypotheses(
                for: segment,
                maximumCount: 2
            )[positiveLabel] ?? 0
        }.max() ?? 0
        let approved = entry.configuration.acceptedForAutomaticRouting
        return ClipboardIntentLabel(
            confidence: rounded(confidence),
            threshold: rounded(threshold),
            isDetected: approved && confidence >= threshold,
            isApprovedForAutomaticRouting: approved
        )
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
                  decoded.schemaVersion == 1 else {
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
