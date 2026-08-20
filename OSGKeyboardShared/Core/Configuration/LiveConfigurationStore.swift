// LiveConfigurationStore.swift
// OSGKeyboard · Shared
//
// In-memory settings snapshot for connection checks and model probes.
// Reads the values the user is editing — not a delayed Keychain re-fetch.

import Foundation

public struct LiveConfigurationSnapshot {
    public let providerId: String
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let asrProviderId: String
    public let asrBaseURL: String
    public let asrApiKey: String
    public let asrModel: String
    public let engineMode: String
    public let credentialSource: CredentialSource
    public let polishIntensity: PolishIntensity
    public let aiResponseLength: AIResponseLength
    public let llmThinkingEnabled: Bool
    public let personalDictionary: PersonalDictionary
    public let polishStyleCatalog: PolishStyleCatalog
    public let activePolishStyleId: String
    public let detectedAppContext: (context: AppContext, observedAt: Date)?
    public let cloudASRPersistence: UserDefaults

    public init(
        providerId: String,
        baseURL: String,
        apiKey: String,
        model: String,
        asrProviderId: String,
        asrBaseURL: String,
        asrApiKey: String,
        asrModel: String,
        engineMode: String,
        credentialSource: CredentialSource = .byok,
        polishIntensity: PolishIntensity,
        aiResponseLength: AIResponseLength = .default,
        llmThinkingEnabled: Bool,
        personalDictionary: PersonalDictionary,
        polishStyleCatalog: PolishStyleCatalog,
        activePolishStyleId: String,
        detectedAppContext: (context: AppContext, observedAt: Date)?,
        cloudASRPersistence: UserDefaults
    ) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.asrProviderId = asrProviderId
        self.asrBaseURL = asrBaseURL
        self.asrApiKey = asrApiKey
        self.asrModel = asrModel
        self.engineMode = engineMode
        self.credentialSource = credentialSource
        self.polishIntensity = polishIntensity
        self.aiResponseLength = aiResponseLength
        self.llmThinkingEnabled = llmThinkingEnabled
        self.personalDictionary = personalDictionary
        self.polishStyleCatalog = polishStyleCatalog
        self.activePolishStyleId = activePolishStyleId
        self.detectedAppContext = detectedAppContext
        self.cloudASRPersistence = cloudASRPersistence
    }

    /// Build from live `ProviderConfig` plus persisted App Group extras.
    public init(config: ProviderConfig, fallback: AppGroupStore) {
        self.init(
            providerId: config.providerId,
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model,
            asrProviderId: config.asrProviderId,
            asrBaseURL: config.asrBaseURL,
            asrApiKey: config.asrApiKey,
            asrModel: config.asrModel,
            engineMode: config.engineMode,
            credentialSource: config.credentialSource,
            polishIntensity: config.polishIntensity,
            aiResponseLength: config.aiResponseLength,
            llmThinkingEnabled: config.llmThinkingEnabled,
            personalDictionary: fallback.personalDictionary,
            polishStyleCatalog: fallback.polishStyleCatalog,
            activePolishStyleId: fallback.activePolishStyleId,
            detectedAppContext: fallback.detectedAppContext,
            cloudASRPersistence: fallback.defaults
        )
    }
}

/// Ephemeral `ConfigurationStore` backed by an immutable capture of the edited
/// values. API keys remain in this in-memory snapshot and are never persisted
/// by the store; `@unchecked Sendable` covers the referenced UserDefaults handle.
public struct LiveConfigurationStore: ConfigurationStore, @unchecked Sendable {
    private let snapshot: LiveConfigurationSnapshot

    public init(snapshot: LiveConfigurationSnapshot) {
        self.snapshot = snapshot
    }

    public init(config: ProviderConfig, fallback: AppGroupStore) {
        self.init(snapshot: LiveConfigurationSnapshot(config: config, fallback: fallback))
    }

    public var providerId: String { snapshot.providerId }
    public var baseURL: String { snapshot.baseURL }
    public var apiKey: String { snapshot.apiKey }
    public var model: String { snapshot.model }
    public var asrProviderId: String { snapshot.asrProviderId }
    public var asrBaseURL: String { snapshot.asrBaseURL }
    public var asrApiKey: String { snapshot.asrApiKey }
    public var asrModel: String { snapshot.asrModel }
    public var engineMode: String { snapshot.engineMode }
    public var credentialSource: CredentialSource { snapshot.credentialSource }
    public var polishIntensity: PolishIntensity { snapshot.polishIntensity }
    public var aiResponseLength: AIResponseLength { snapshot.aiResponseLength }
    public var llmThinkingEnabled: Bool { snapshot.llmThinkingEnabled }
    public var personalDictionary: PersonalDictionary { snapshot.personalDictionary }
    public var polishStyleCatalog: PolishStyleCatalog { snapshot.polishStyleCatalog }
    public var activePolishStyleId: String { snapshot.activePolishStyleId }
    public var detectedAppContext: (context: AppContext, observedAt: Date)? { snapshot.detectedAppContext }
    public var cloudASRPersistence: UserDefaults { snapshot.cloudASRPersistence }

    public func makeClient(
        taskKind: ManagedGatewayTaskKind?,
        requestPurpose: ManagedGatewayRequestPurpose?
    ) -> LLMClient {
        if credentialSource == .managed {
            return ManagedLLMClient(
                capability: .polish,
                taskKind: taskKind,
                requestPurpose: requestPurpose,
                grants: GatewayGrantCoordinator()
            )
        }
        return LLMClientFactory.make(
            providerId: providerId,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            thinkingEnabled: llmThinkingEnabled
        )
    }
}
