// PersonalReplyStyleSection.swift
// OSGKeyboard · Main App
//
// The distilled personal style, shown at the top of the Skills tab.
//
// It deliberately does not live on the Styles page: a learned pack injected
// into voice polish outranks the core filler / repetition cleanup and puts the
// speaker's disfluencies back into the transcript. Styles shape dictation; this
// shapes AI replies, and the two selections are independent.

import OSGKeyboardShared
import SwiftUI

struct PersonalReplyStyleErrorAlert {
    let title: String
    let message: String
}

@MainActor
struct PersonalReplyStyleSection: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var history = SpeechHistoryStore.shared

    @State private var catalog = AppGroupStore().polishStyleCatalog
    @State private var enabledStyleID = AppGroupStore().personalReplyStyleId
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var editingPack: PolishStylePack?
    /// Evidence from the generation under review; persisted only on save.
    @State private var pendingLearning: PendingLearning?
    @State private var errorAlert: PersonalReplyStyleErrorAlert?

    private struct PendingLearning {
        let packID: String
        let prior: PolishStyleLearningPriorEvidence
    }

    private let store = AppGroupStore()
    private let learningState = PersonalStyleLearningStateStore.shared
    private let generator: LearnedStyleGenerator

    #if DEBUG
    /// Concept-film recordings start generation after this delay; `simctl`
    /// cannot tap the button. Nil keeps the production tap-to-generate flow.
    static var debugAutoGenerationDelay: Duration?
    /// Shows the App Store 2,500-character gate instead of the internal one.
    static var debugUsesReleaseCharacterGate = false
    #endif

    init(
        initialEditingPack: PolishStylePack? = nil,
        generator: @escaping LearnedStyleGenerator = { corpus, replyExamples, language, prior in
            try await PolishStyleLearningService(store: AppGroupStore())
                .learnStyle(
                    from: corpus,
                    replyExamples: replyExamples,
                    outputLanguage: language,
                    minimumEffectiveCharacterCount:
                        AppDistributionChannel.allowsInternalTools
                            ? PolishStyleLearningCorpusBuilder
                                .testBuildEffectiveCharacterCount
                            : PolishStyleLearningCorpusBuilder
                                .requiredEffectiveCharacterCount,
                    prior: prior
                )
        }
    ) {
        _editingPack = State(initialValue: initialEditingPack)
        self.generator = generator
    }

    var body: some View {
        CardSection(title: AppL10n.string("personalReplyStyle.section")) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let pack = learnedPack {
                    learnedCard(pack, corpus: corpus)
                } else {
                    generationCard
                }
            }
        }
        .sheet(item: $editingPack, onDismiss: { pendingLearning = nil }) { pack in
            PolishStyleEditorSheet(
                pack: pack,
                isNew: !catalog.entries.contains(where: { $0.id == pack.id })
            ) { saved in
                save(saved)
            }
        }
        .alert(
            Text(errorAlert?.title ?? ""),
            isPresented: Binding(
                get: { errorAlert != nil },
                set: { if !$0 { errorAlert = nil } }
            )
        ) {
            Button(AppL10n.string("common.done")) { errorAlert = nil }
        } message: {
            Text(errorAlert?.message ?? "")
        }
        .task {
            reload()
            #if DEBUG
            if let delay = Self.debugAutoGenerationDelay {
                try? await Task.sleep(for: delay)
                generate(from: corpus)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .polishStylesDidSyncFromCloud)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            reload()
        }
        .onDisappear { cancelGeneration() }
    }

    // MARK: - Data

    private var corpus: PolishStyleLearningCorpus {
        PolishStyleLearningCorpusBuilder.build(from: history.snapshot())
    }

    /// Debug + TestFlight builds unlock generation at a lower character gate so
    /// internal testers can exercise the pipeline.
    private var minimumCharacterCount: Int {
        #if DEBUG
        if Self.debugUsesReleaseCharacterGate {
            return PolishStyleLearningCorpusBuilder.requiredEffectiveCharacterCount
        }
        #endif
        return AppDistributionChannel.allowsInternalTools
            ? PolishStyleLearningCorpusBuilder.testBuildEffectiveCharacterCount
            : PolishStyleLearningCorpusBuilder.requiredEffectiveCharacterCount
    }

    /// Without a prior the full corpus gate applies; with one, only the
    /// characters dictated since the last saved generation count.
    private func isEligible(
        _ corpus: PolishStyleLearningCorpus,
        prior: PolishStyleLearningPriorEvidence? = nil
    ) -> Bool {
        guard let prior else {
            return corpus.effectiveCharacterCount >= minimumCharacterCount
        }
        return corpus.examples(after: prior.learnedThrough).effectiveCharacterCount
            >= PolishStyleLearningCorpusBuilder.incrementalEffectiveCharacterCount
    }

    private var learnedPack: PolishStylePack? {
        PolishStylePackCatalog.latestPersonalReplyStyle(userCatalog: catalog)
    }

    // MARK: - Cards

    private func learnedCard(
        _ pack: PolishStylePack,
        corpus: PolishStyleLearningCorpus
    ) -> some View {
        let prior = learningState.prior(for: pack)
        let canRegenerate = isEligible(corpus, prior: prior) && !isGenerating
        let actionShape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "person.wave.2.fill")
                    .font(TypeStyle.headline)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        palette.textPrimary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.displayName(language: config.uiLanguage))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string("personalReplyStyle.generated.description"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    editingPack = pack
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(palette.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .accessibilityLabel(Text(AppL10n.string("polishStyles.edit")))
            }

            if let metadata = pack.learningMetadata {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "clock")
                        Text(AppL10n.string("personalReplyStyle.generatedAt"))
                        Text(metadata.generatedAt, format: .dateTime.year().month().day())
                    }
                    Text(
                        AppL10n.format(
                            "personalReplyStyle.evidenceSummary",
                            Int64(metadata.asrEffectiveCharacterCount),
                            Int64(metadata.replyExampleCount),
                            Int64(metadata.replyFinalEditCount)
                        )
                    )
                    Text(
                        AppL10n.format(
                            "personalReplyStyle.confidence",
                            Self.confidencePercentage(metadata.confidence)
                        )
                    )
                    if let prior {
                        Text(
                            AppL10n.format(
                                "personalReplyStyle.newSinceLast",
                                Int64(
                                    corpus.examples(after: prior.learnedThrough)
                                        .effectiveCharacterCount
                                ),
                                Int64(
                                    PolishStyleLearningCorpusBuilder
                                        .incrementalEffectiveCharacterCount
                                )
                            )
                        )
                        .accessibilityIdentifier("personalReplyStyle.newSinceLast")
                    }
                }
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
            }

            Button {
                generate(from: corpus, replacing: pack)
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(
                        AppL10n.string(
                            isGenerating
                                ? "personalReplyStyle.regenerating"
                                : "personalReplyStyle.regenerate"
                        )
                    )
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(canRegenerate ? palette.textPrimary : palette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(palette.surfaceElevated, in: actionShape)
            }
            .buttonStyle(.plain)
            .disabled(!canRegenerate)
            .accessibilityIdentifier("personalReplyStyle.regenerate")
            .accessibilityValue(Text(pack.id))
        }
        .padding(Spacing.lg)
        .surfaceCard()
        .accessibilityIdentifier("personalReplyStyle.card")
    }

    private var generationCard: some View {
        let corpus = corpus
        let required = minimumCharacterCount
        let reachedLimit = catalog.entries.count >= PolishStyleLimits.maximumUserPacks
        let isActionAvailable = isEligible(corpus) && !reachedLimit
        let canGenerate = isActionAvailable && !isGenerating
        let completed = min(corpus.effectiveCharacterCount, required)
        let fraction = required > 0 ? Double(completed) / Double(required) : 0
        let progressDescription = AppL10n.format(
            "personalReplyStyle.progress",
            Int64(corpus.effectiveCharacterCount),
            Int64(required)
        )

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "brain")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(
                        palette.textPrimary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppL10n.string("personalReplyStyle.empty.title"))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string("personalReplyStyle.empty.body"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressTrack(
                segments: [ProgressTrackSegment(fraction: fraction, color: palette.accent)]
            )
            .accessibilityLabel(Text(AppL10n.string("personalReplyStyle.empty.title")))
            .accessibilityValue(Text(progressDescription))

            HStack {
                Text(progressDescription)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)

                Spacer()

                Text(
                    isEligible(corpus)
                        ? AppL10n.string("personalReplyStyle.ready")
                        : AppL10n.format(
                            "personalReplyStyle.remaining",
                            Int64(max(0, required - corpus.effectiveCharacterCount))
                        )
                )
                .font(TypeStyle.caption2)
                .foregroundStyle(isEligible(corpus) ? palette.accent : palette.textTertiary)
            }

            Button {
                generate(from: corpus)
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isActionAvailable ? palette.textOnAccent : palette.textSecondary)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(
                        isGenerating
                            ? AppL10n.string("personalReplyStyle.generating")
                            : AppL10n.string("personalReplyStyle.action")
                    )
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(isActionAvailable ? palette.textOnAccent : palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    isActionAvailable ? palette.accent : palette.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            .accessibilityIdentifier("personalReplyStyle.generate")

            Text(
                reachedLimit
                    ? AppL10n.string("personalReplyStyle.limit")
                    : AppL10n.string("personalReplyStyle.privacy")
            )
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .surfaceCard()
    }

    // MARK: - Actions

    private func generate(
        from corpus: PolishStyleLearningCorpus,
        replacing existingPack: PolishStylePack? = nil
    ) {
        let prior = existingPack.flatMap(learningState.prior(for:))
        guard isEligible(corpus, prior: prior),
              !isGenerating,
              generationTask == nil else { return }
        let id = UUID()
        generationID = id
        isGenerating = true
        generationTask = Task { @MainActor in
            defer { finishGeneration(id: id) }
            do {
                let result = try await generator(
                    corpus,
                    ClipboardReplyFeedbackStore.shared.learningExamples(),
                    config.uiLanguage,
                    prior
                )
                try Task.checkCancellation()
                guard generationID == id, editingPack == nil else { return }
                let generated = result.pack
                // Always let the user inspect and edit the learned prompt before
                // it is saved, synced, or enabled. Saving overwrites the existing
                // style, including any manual edits to it.
                let reviewPack: PolishStylePack
                if let existingPack {
                    reviewPack = PolishStylePack(
                        id: existingPack.id,
                        name: generated.name,
                        prompt: generated.prompt,
                        allowsAddedEmoji: generated.allowsAddedEmoji,
                        learningMetadata: generated.learningMetadata,
                        kind: .user,
                        createdAt: existingPack.createdAt,
                        updatedAt: Date()
                    )
                } else {
                    reviewPack = generated
                }
                pendingLearning = result.prior.map {
                    PendingLearning(packID: reviewPack.id, prior: $0)
                }
                editingPack = reviewPack
            } catch {
                guard generationID == id,
                      !Task.isCancelled,
                      !Self.isCancellation(error) else { return }
                errorAlert = PersonalReplyStyleErrorAlert(
                    title: AppL10n.string("personalReplyStyle.error.title"),
                    message: localizedLearningError(error)
                )
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
        isGenerating = false
    }

    private func finishGeneration(id: UUID) {
        guard generationID == id else { return }
        generationTask = nil
        generationID = nil
        isGenerating = false
    }

    /// Saving a personal style enables it for replies. It must never touch
    /// `activePolishStyleId` — the store would reject it anyway, but writing
    /// there at all is what used to conflate the two pipelines.
    private func save(_ pack: PolishStylePack) -> Bool {
        var updatedCatalog = catalog
        do {
            try updatedCatalog.upsert(pack)
            catalog = updatedCatalog
            store.setPolishStyleCatalog(catalog)
            store.setPersonalReplyStyleId(pack.id)
            enabledStyleID = store.personalReplyStyleId
            if let pendingLearning, pendingLearning.packID == pack.id {
                learningState.save(pendingLearning.prior, for: pack)
                self.pendingLearning = nil
            }
            pushSync()
            return true
        } catch {
            errorAlert = PersonalReplyStyleErrorAlert(
                title: AppL10n.string("polishStyles.error.title"),
                message: localized(error)
            )
            return false
        }
    }

    /// Distilling a style *is* the decision to use it, so there is no on/off
    /// switch. A pack that exists without being the enabled ID — an opt-out
    /// left by an older build, or a cloud merge that dropped the pointer — is
    /// adopted here, so the card can never show a style that does nothing.
    private func reload() {
        catalog = store.polishStyleCatalog
        enabledStyleID = store.personalReplyStyleId
        guard enabledStyleID.isEmpty, let pack = learnedPack else { return }
        store.setPersonalReplyStyleId(pack.id)
        enabledStyleID = store.personalReplyStyleId
        pushSync()
    }

    private func pushSync() {
        Task {
            try? await PolishStyleCloudSync.shared.pushLocalIfEnabled(catalog)
            try? await AppCloudSync.shared.settingsSyncService.pushLocalIfEnabled()
        }
    }

    // MARK: - Errors

    private func localizedLearningError(_ error: Error) -> String {
        switch error as? PolishStyleLearningError {
        case .insufficientCorpus:
            return AppL10n.string("personalReplyStyle.error.insufficient")
        case .invalidResponse:
            return AppL10n.string("polishStyles.learn.error.invalidResponse")
        case .promptTooLong:
            return AppL10n.string("polishStyles.learn.error.promptTooLong")
        case .requestTooLarge:
            return AppL10n.string("polishStyles.learn.error.requestTooLarge")
        case nil:
            return PolishStyleLearningFailureMessage.localized(
                for: error,
                language: config.uiLanguage
            ) ?? AppL10n.string("polishStyles.learn.error.request")
        }
    }

    private func localized(_ error: Error) -> String {
        switch error as? PolishStyleValidationError {
        case .emptyName: return AppL10n.string("polishStyles.error.emptyName")
        case .emptyPrompt: return AppL10n.string("polishStyles.error.emptyPrompt")
        case .tooManyUserPacks: return AppL10n.string("polishStyles.error.limit")
        case .promptTooLong: return AppL10n.string("polishStyles.error.promptTooLong")
        case .builtinIsImmutable: return AppL10n.string("polishStyles.error.builtin")
        case nil: return AppL10n.string("polishStyles.error.generic")
        }
    }

    private static func confidencePercentage(_ confidence: Double) -> Int64 {
        Int64((min(max(confidence, 0), 1) * 100).rounded())
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? LLMError) == .cancelled
    }
}
