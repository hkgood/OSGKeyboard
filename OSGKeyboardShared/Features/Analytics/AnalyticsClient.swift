// AnalyticsClient.swift
// OSGKeyboard · Shared
//
// Synchronous, type-safe fire-and-forget API. Every asynchronous task owns only
// Sendable dependencies and analytics failures never escape into feature code.

import Foundation

public protocol AnalyticsClient: Sendable {
    func recordSessionActivity()
    func recordKeyboardActivated()
    func recordPurchaseViewed()
    func recordPurchaseStarted()
    func recordPurchaseCancelled()
    func recordReferralShared()
    func recordInviteOpened(
        acquisitionChannel: AnalyticsAcquisitionChannel,
        surface: AnalyticsSurface
    )
    func startAIFeature(
        _ feature: AnalyticsFeature,
        executionMode: AnalyticsExecutionMode
    ) -> any AnalyticsAIOperation
}

public extension AnalyticsClient {
    func recordInviteOpened(
        acquisitionChannel: AnalyticsAcquisitionChannel = .referral
    ) {
        recordInviteOpened(
            acquisitionChannel: acquisitionChannel,
            surface: .inviteWeb
        )
    }
}

public protocol AnalyticsAIOperation: Sendable {
    func succeed()
    func fail(category: AnalyticsFailureCategory)
    func cancel()
}

public final class LiveAnalyticsClient: AnalyticsClient, Sendable {
    private let repository: AnalyticsRepository
    private let context: AnalyticsBootstrapContext
    private let monotonicClock: any AnalyticsMonotonicClock
    private let trigger: any AnalyticsUploadTriggering

    public init(
        repository: AnalyticsRepository,
        context: AnalyticsBootstrapContext,
        monotonicClock: any AnalyticsMonotonicClock = SystemAnalyticsMonotonicClock(),
        trigger: any AnalyticsUploadTriggering = NoopAnalyticsUploadTrigger()
    ) {
        self.repository = repository
        self.context = context
        self.monotonicClock = monotonicClock
        self.trigger = trigger
    }

    public func recordSessionActivity() {
        Task {
            await repository.recordSessionIfNeeded(context: context)
            await trigger.requestUpload()
        }
    }

    public func recordKeyboardActivated() {
        enqueue(eventType: .keyboardActivated)
    }

    public func recordPurchaseViewed() {
        enqueue(eventType: .purchaseViewed)
    }

    public func recordPurchaseStarted() {
        enqueue(eventType: .purchaseStarted)
    }

    public func recordPurchaseCancelled() {
        enqueue(
            eventType: .purchaseCancelled,
            dimensions: AnalyticsEventDimensions(failureCategory: .cancelled)
        )
    }

    public func recordReferralShared() {
        enqueue(eventType: .referralShared)
    }

    public func recordInviteOpened(
        acquisitionChannel: AnalyticsAcquisitionChannel,
        surface: AnalyticsSurface
    ) {
        enqueue(
            eventType: .inviteOpened,
            surfaceOverride: surface,
            dimensions: AnalyticsEventDimensions(
                acquisitionChannel: acquisitionChannel
            )
        )
    }

    public func startAIFeature(
        _ feature: AnalyticsFeature,
        executionMode: AnalyticsExecutionMode
    ) -> any AnalyticsAIOperation {
        let startNanoseconds = monotonicClock.nowNanoseconds()
        let dimensions = AnalyticsEventDimensions(
            feature: feature,
            executionMode: executionMode
        )
        let startedTask = enqueue(
            eventType: .aiFeatureStarted,
            dimensions: dimensions
        )
        return LiveAnalyticsAIOperation(
            repository: repository,
            context: context,
            feature: feature,
            executionMode: executionMode,
            startNanoseconds: startNanoseconds,
            startedTask: startedTask,
            monotonicClock: monotonicClock,
            trigger: trigger
        )
    }

    @discardableResult
    private func enqueue(
        eventType: AnalyticsEventType,
        surfaceOverride: AnalyticsSurface? = nil,
        dimensions: AnalyticsEventDimensions = .none
    ) -> Task<Void, Never> {
        let recordTask = Task {
            await repository.record(
                eventType: eventType,
                context: context,
                surfaceOverride: surfaceOverride,
                dimensions: dimensions
            )
        }
        Task {
            await recordTask.value
            await trigger.requestUpload()
        }
        return recordTask
    }
}

public final class LiveAnalyticsAIOperation: AnalyticsAIOperation, @unchecked Sendable {
    private let repository: AnalyticsRepository
    private let context: AnalyticsBootstrapContext
    private let feature: AnalyticsFeature
    private let executionMode: AnalyticsExecutionMode
    private let startNanoseconds: UInt64
    private let startedTask: Task<Void, Never>
    private let monotonicClock: any AnalyticsMonotonicClock
    private let trigger: any AnalyticsUploadTriggering
    private let terminalLock = NSLock()
    private var reachedTerminalState = false

    init(
        repository: AnalyticsRepository,
        context: AnalyticsBootstrapContext,
        feature: AnalyticsFeature,
        executionMode: AnalyticsExecutionMode,
        startNanoseconds: UInt64,
        startedTask: Task<Void, Never>,
        monotonicClock: any AnalyticsMonotonicClock,
        trigger: any AnalyticsUploadTriggering
    ) {
        self.repository = repository
        self.context = context
        self.feature = feature
        self.executionMode = executionMode
        self.startNanoseconds = startNanoseconds
        self.startedTask = startedTask
        self.monotonicClock = monotonicClock
        self.trigger = trigger
    }

    public func succeed() {
        finish(eventType: .aiFeatureSucceeded, failureCategory: nil)
    }

    public func fail(category: AnalyticsFailureCategory) {
        finish(eventType: .aiFeatureFailed, failureCategory: category)
    }

    public func cancel() {
        fail(category: .cancelled)
    }

    private func finish(
        eventType: AnalyticsEventType,
        failureCategory: AnalyticsFailureCategory?
    ) {
        terminalLock.lock()
        guard !reachedTerminalState else {
            terminalLock.unlock()
            return
        }
        reachedTerminalState = true
        terminalLock.unlock()

        let endNanoseconds = monotonicClock.nowNanoseconds()
        let elapsed = endNanoseconds >= startNanoseconds
            ? endNanoseconds - startNanoseconds
            : 0
        let dimensions = AnalyticsEventDimensions(
            feature: feature,
            executionMode: executionMode,
            failureCategory: failureCategory,
            durationBucket: AnalyticsDurationBucket(elapsedNanoseconds: elapsed)
        )
        Task {
            // This explicit dependency guarantees STARTED reaches the repository
            // before any terminal event, even when completion is immediate.
            await startedTask.value
            await repository.record(
                eventType: eventType,
                context: context,
                dimensions: dimensions
            )
            await trigger.requestUpload()
        }
    }
}

public struct NoopAnalyticsAIOperation: AnalyticsAIOperation {
    public init() {}

    public func succeed() {}
    public func fail(category: AnalyticsFailureCategory) {}
    public func cancel() {}
}

public struct NoopAnalyticsClient: AnalyticsClient {
    public init() {}

    public func recordSessionActivity() {}
    public func recordKeyboardActivated() {}
    public func recordPurchaseViewed() {}
    public func recordPurchaseStarted() {}
    public func recordPurchaseCancelled() {}
    public func recordReferralShared() {}

    public func recordInviteOpened(
        acquisitionChannel: AnalyticsAcquisitionChannel,
        surface: AnalyticsSurface
    ) {}

    public func startAIFeature(
        _ feature: AnalyticsFeature,
        executionMode: AnalyticsExecutionMode
    ) -> any AnalyticsAIOperation {
        NoopAnalyticsAIOperation()
    }
}

public typealias AnalyticsAISpan = any AnalyticsAIOperation

public struct AnalyticsRuntime: Sendable {
    public let repository: AnalyticsRepository
    public let client: any AnalyticsClient
    public let uploadCoordinator: AnalyticsUploadCoordinator
    public let context: AnalyticsBootstrapContext

    private init(
        surface: AnalyticsSurface,
        environment: AnalyticsEnvironment,
        repositoryConfiguration: AnalyticsRepositoryConfiguration,
        uploadConfiguration: AnalyticsUploadConfiguration,
        network: any AnalyticsNetworking,
        bearerProvider: (any AnalyticsBearerProviding)?,
        wallClock: any AnalyticsWallClock,
        monotonicClock: any AnalyticsMonotonicClock,
        uuidGenerator: any AnalyticsUUIDGenerating,
        random: any AnalyticsRandomGenerating,
        trigger: any AnalyticsUploadTriggering,
        logger: any AnalyticsLogging
    ) {
        let context = AnalyticsBootstrapContext(
            surface: surface,
            environment: environment
        )
        let repository = AnalyticsRepository(
            configuration: repositoryConfiguration,
            clock: wallClock,
            uuidGenerator: uuidGenerator
        )
        self.context = context
        self.repository = repository
        client = LiveAnalyticsClient(
            repository: repository,
            context: context,
            monotonicClock: monotonicClock,
            trigger: trigger
        )
        uploadCoordinator = AnalyticsUploadCoordinator(
            repository: repository,
            configuration: uploadConfiguration,
            network: network,
            bearerProvider: bearerProvider,
            clock: wallClock,
            uuidGenerator: uuidGenerator,
            random: random,
            logger: logger
        )
    }

    /// Main-app runtime. A bearer provider may be supplied by host-only account
    /// code without making the shared framework depend on that code.
    public static func mainApp(
        environment: AnalyticsEnvironment,
        repositoryConfiguration: AnalyticsRepositoryConfiguration = .appGroupDefault(),
        uploadConfiguration: AnalyticsUploadConfiguration,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork(),
        bearerProvider: (any AnalyticsBearerProviding)? = nil,
        wallClock: any AnalyticsWallClock = SystemAnalyticsWallClock(),
        monotonicClock: any AnalyticsMonotonicClock = SystemAnalyticsMonotonicClock(),
        uuidGenerator: any AnalyticsUUIDGenerating = SystemAnalyticsUUIDGenerator(),
        random: any AnalyticsRandomGenerating = SystemAnalyticsRandomGenerator(),
        trigger: any AnalyticsUploadTriggering = NoopAnalyticsUploadTrigger(),
        logger: any AnalyticsLogging = NoopAnalyticsLogger()
    ) -> Self {
        Self(
            surface: .app,
            environment: environment,
            repositoryConfiguration: repositoryConfiguration,
            uploadConfiguration: uploadConfiguration,
            network: network,
            bearerProvider: bearerProvider,
            wallClock: wallClock,
            monotonicClock: monotonicClock,
            uuidGenerator: uuidGenerator,
            random: random,
            trigger: trigger,
            logger: logger
        )
    }

    /// Keyboard-extension runtime. This factory intentionally has no bearer
    /// parameter, so extension uploads are anonymous by construction.
    public static func keyboardExtension(
        environment: AnalyticsEnvironment,
        repositoryConfiguration: AnalyticsRepositoryConfiguration = .appGroupDefault(),
        uploadConfiguration: AnalyticsUploadConfiguration,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork(),
        wallClock: any AnalyticsWallClock = SystemAnalyticsWallClock(),
        monotonicClock: any AnalyticsMonotonicClock = SystemAnalyticsMonotonicClock(),
        uuidGenerator: any AnalyticsUUIDGenerating = SystemAnalyticsUUIDGenerator(),
        random: any AnalyticsRandomGenerating = SystemAnalyticsRandomGenerator(),
        trigger: any AnalyticsUploadTriggering = NoopAnalyticsUploadTrigger(),
        logger: any AnalyticsLogging = NoopAnalyticsLogger()
    ) -> Self {
        Self(
            surface: .keyboard,
            environment: environment,
            repositoryConfiguration: repositoryConfiguration,
            uploadConfiguration: uploadConfiguration,
            network: network,
            bearerProvider: nil,
            wallClock: wallClock,
            monotonicClock: monotonicClock,
            uuidGenerator: uuidGenerator,
            random: random,
            trigger: trigger,
            logger: logger
        )
    }

    public func setEnabled(_ enabled: Bool) async {
        await repository.setEnabled(enabled)
    }

    /// Host-only explicit initialization point. Call after processing the
    /// cold-start URL so FIRST_OPEN receives the final acquisition channel.
    public func prepare(
        firstOpenAcquisitionChannel: AnalyticsAcquisitionChannel = .unknown
    ) async {
        await repository.prepare(
            using: context,
            firstOpenAcquisitionChannel: firstOpenAcquisitionChannel
        )
    }

    public func isEnabled() async -> Bool {
        await repository.isEnabled()
    }

    public func observeAccount(
        stableIdentifier: String
    ) async -> AnalyticsAccountObservation {
        await repository.observeAccount(
            stableIdentifier: stableIdentifier
        )
    }

    public func handleAccountDeletion() async {
        await repository.handleAccountDeletion()
    }
}
