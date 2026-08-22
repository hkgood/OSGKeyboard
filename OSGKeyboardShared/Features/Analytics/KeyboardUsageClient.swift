// KeyboardUsageClient.swift
// OSGKeyboard · Shared
//
// Fire-and-forget numeric recording facade. Calls are serialized per process so
// a UTC rollover cannot finalize a day ahead of an earlier queued insertion.

import Foundation

public protocol KeyboardUsageRecording: Sendable {
    func recordManualKeyboardCounts(
        _ counts: KeyboardUsageCharacterCounts,
        sessionID: UUID
    )
}

public struct NoopKeyboardUsageRecorder: KeyboardUsageRecording {
    public init() {}

    public func recordManualKeyboardCounts(
        _ counts: KeyboardUsageCharacterCounts,
        sessionID: UUID
    ) {}
}

public final class LiveKeyboardUsageRecorder:
    KeyboardUsageRecording,
    @unchecked Sendable {
    private let analyticsRepository: AnalyticsRepository
    private let repository: KeyboardUsageRepository
    private let environment: AnalyticsEnvironment
    private let clock: any AnalyticsWallClock
    private let trigger: any AnalyticsUploadTriggering
    private let lock = NSLock()
    private var tailTask: Task<Void, Never>?

    public init(
        analyticsRepository: AnalyticsRepository,
        repository: KeyboardUsageRepository,
        environment: AnalyticsEnvironment,
        clock: any AnalyticsWallClock = SystemAnalyticsWallClock(),
        trigger: any AnalyticsUploadTriggering = NoopAnalyticsUploadTrigger()
    ) {
        self.analyticsRepository = analyticsRepository
        self.repository = repository
        self.environment = environment
        self.clock = clock
        self.trigger = trigger
    }

    public func recordManualKeyboardCounts(
        _ counts: KeyboardUsageCharacterCounts,
        sessionID: UUID
    ) {
        guard !counts.isEmpty else { return }
        let occurredAt = clock.now()
        let analyticsRepository = analyticsRepository
        let repository = repository
        let environment = environment
        let trigger = trigger

        lock.withLock {
            let previous = tailTask
            tailTask = Task {
                await previous?.value
                guard let installationID =
                        await analyticsRepository.installationIdentifierIfEnabled() else {
                    return
                }
                await repository.record(
                    counts: counts,
                    sessionID: sessionID,
                    installationID: installationID,
                    occurredAt: occurredAt,
                    environment: environment
                )
                await trigger.requestUpload()
            }
        }
    }

    func waitForPendingRecords() async {
        let task = lock.withLock { tailTask }
        await task?.value
    }
}

public struct KeyboardUsageRuntime: Sendable {
    public let repository: KeyboardUsageRepository
    public let recorder: any KeyboardUsageRecording
    public let uploadCoordinator: KeyboardUsageUploadCoordinator

    public init(
        environment: AnalyticsEnvironment,
        analyticsRepository: AnalyticsRepository,
        repositoryConfiguration: KeyboardUsageRepositoryConfiguration = .appGroupDefault(),
        uploadConfiguration: KeyboardUsageUploadConfiguration,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork(),
        bearerProvider: (any AnalyticsBearerProviding)? = nil,
        wallClock: any AnalyticsWallClock = SystemAnalyticsWallClock(),
        uuidGenerator: any AnalyticsUUIDGenerating = SystemAnalyticsUUIDGenerator(),
        random: any AnalyticsRandomGenerating = SystemAnalyticsRandomGenerator(),
        trigger: any AnalyticsUploadTriggering = NoopAnalyticsUploadTrigger(),
        logger: any AnalyticsLogging = NoopAnalyticsLogger()
    ) {
        let repository = KeyboardUsageRepository(
            configuration: repositoryConfiguration,
            clock: wallClock,
            uuidGenerator: uuidGenerator
        )
        self.repository = repository
        recorder = LiveKeyboardUsageRecorder(
            analyticsRepository: analyticsRepository,
            repository: repository,
            environment: environment,
            clock: wallClock,
            trigger: trigger
        )
        uploadCoordinator = KeyboardUsageUploadCoordinator(
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
}
