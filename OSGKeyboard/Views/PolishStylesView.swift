// PolishStylesView.swift
// OSGKeyboard · Main App
//
// Main-app editor for complete polish writing personalities. The keyboard
// reads the selected pack from App Group storage on the next polish request.

import OSGKeyboardShared
import SwiftUI

typealias LearnedStyleGenerator = @MainActor @Sendable (
    PolishStyleLearningCorpus,
    [PolishStyleReplyLearningExample],
    AppUILanguage
) async throws -> PolishStylePack

private struct PolishStyleErrorAlert {
    let title: String
    let message: String
}

@MainActor
struct PolishStylesView: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var history = SpeechHistoryStore.shared

    @State private var catalog = AppGroupStore().polishStyleCatalog
    @State private var activeID = AppGroupStore().activePolishStyleId
    /// Drives the editor sheet via `sheet(item:)` so create/edit always
    /// receives a concrete pack (avoids `isPresented` + nil race showing defaults).
    @State private var editingPack: PolishStylePack?
    @State private var viewingPack: PolishStylePack?
    @State private var errorAlert: PolishStyleErrorAlert?
    @State private var isGeneratingLearnedStyle = false
    @State private var learnedStyleGenerationTask: Task<Void, Never>?
    @State private var learnedStyleGenerationID: UUID?

    private let store = AppGroupStore()
    private let learnedStyleGenerator: LearnedStyleGenerator
    private let pullsCloudStylesOnAppear: Bool
    private let columns = [
        GridItem(.flexible(), spacing: CardLayoutMetrics.compactItemSpacing),
        GridItem(.flexible(), spacing: CardLayoutMetrics.compactItemSpacing)
    ]

    init(
        initialEditingPack: PolishStylePack? = nil,
        pullsCloudStylesOnAppear: Bool = true,
        learnedStyleGenerator: @escaping LearnedStyleGenerator = { corpus, replyExamples, language in
            try await PolishStyleLearningService(store: AppGroupStore())
                .generateStyle(
                    from: corpus,
                    replyExamples: replyExamples,
                    outputLanguage: language,
                    minimumEffectiveCharacterCount:
                        AppDistributionChannel.allowsInternalTools
                            ? PolishStyleLearningCorpusBuilder
                                .testBuildEffectiveCharacterCount
                            : PolishStyleLearningCorpusBuilder
                                .requiredEffectiveCharacterCount
                )
        }
    ) {
        _editingPack = State(initialValue: initialEditingPack)
        self.pullsCloudStylesOnAppear = pullsCloudStylesOnAppear
        self.learnedStyleGenerator = learnedStyleGenerator
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent {
                    if let learnedStylePack {
                        learnedStyleCard(
                            learnedStylePack,
                            corpus: styleLearningCorpus
                        )
                    } else {
                        styleLearningCard
                    }
                    packGridSection(
                        title: "polishStyles.builtin.section",
                        packs: PolishStylePackCatalog.BuiltinStyleGroup.practical.packs
                    )
                    packGridSection(
                        title: "polishStyles.fun.section",
                        packs: PolishStylePackCatalog.BuiltinStyleGroup.fun.packs
                    )
                    if !remainingUserPacks.isEmpty {
                        packGridSection(
                            title: "polishStyles.custom.section",
                            packs: remainingUserPacks
                        )
                    }
                }
                .tabBarScrollBottomPadding()
            }
            .scrollClipDisabled()
            .background(palette.background)
            .navigationTitle("polishStyles.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingPack = Self.makeDraftPack()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(palette.textPrimary)
                    .disabled(
                        catalog.entries.count >= PolishStyleLimits.maximumUserPacks
                            || isGeneratingLearnedStyle
                    )
                    .accessibilityLabel(Text("polishStyles.add"))
                }
            }
        }
        .sheet(item: $editingPack) { pack in
            PolishStyleEditorSheet(
                pack: pack,
                isNew: !catalog.entries.contains(where: { $0.id == pack.id })
            ) { saved in
                save(saved)
            }
        }
        .sheet(item: $viewingPack) { pack in
            PolishStylePromptDetailSheet(pack: pack, language: config.uiLanguage)
        }
        .alert(
            Text(errorAlert?.title ?? ""),
            isPresented: Binding(
                get: { errorAlert != nil },
                set: { if !$0 { errorAlert = nil } }
            )
        ) {
            Button("common.done") { errorAlert = nil }
        } message: {
            Text(errorAlert?.message ?? "")
        }
        .task {
            reload()
            guard pullsCloudStylesOnAppear else { return }
            await PolishStyleCloudSync.shared.pullAndMergeIfEnabled()
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .polishStylesDidSyncFromCloud)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            reload()
        }
        .onDisappear {
            cancelLearnedStyleGeneration()
        }
    }

    private var styleLearningCorpus: PolishStyleLearningCorpus {
        PolishStyleLearningCorpusBuilder.build(from: history.snapshot())
    }

    /// Minimum effective character count required to unlock personal style
    /// generation. Debug + TestFlight builds use a lower 1,250-character
    /// gate so internal testers can still exercise the pipeline; the
    /// previous 0 / "unlimited" bypass has been removed.
    private var styleLearningMinimumCharacterCount: Int {
        AppDistributionChannel.allowsInternalTools
            ? PolishStyleLearningCorpusBuilder.testBuildEffectiveCharacterCount
            : PolishStyleLearningCorpusBuilder.requiredEffectiveCharacterCount
    }

    private func isEligibleForStyleGeneration(
        _ corpus: PolishStyleLearningCorpus
    ) -> Bool {
        corpus.effectiveCharacterCount >= styleLearningMinimumCharacterCount
    }

    private var learnedStylePack: PolishStylePack? {
        catalog.entries
            .filter { $0.learningMetadata != nil }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var remainingUserPacks: [PolishStylePack] {
        let featuredID = learnedStylePack?.id
        return PolishStylePackCatalog.all(userCatalog: catalog)
            .filter { $0.kind == .user && $0.id != featuredID }
    }

    private var styleLearningCard: some View {
        let corpus = styleLearningCorpus
        let required = styleLearningMinimumCharacterCount
        let reachedLimit = catalog.entries.count >= PolishStyleLimits.maximumUserPacks
        let isActionAvailable = isEligibleForStyleGeneration(corpus) && !reachedLimit
        let canGenerate = isActionAvailable && !isGeneratingLearnedStyle
        let completedCharacterCount = min(corpus.effectiveCharacterCount, required)
        let learnedFraction = required > 0
            ? Double(completedCharacterCount) / Double(required)
            : 0
        let progressDescription = AppL10n.format(
            "polishStyles.learn.progress",
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
                    Text("polishStyles.learn.title")
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text("polishStyles.learn.body")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressTrack(
                segments: [
                    ProgressTrackSegment(
                        fraction: learnedFraction,
                        color: palette.accent
                    )
                ]
            )
            .accessibilityLabel(Text("polishStyles.learn.title"))
            .accessibilityValue(Text(progressDescription))

            HStack {
                Text(progressDescription)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)

                Spacer()

                Text(
                    isEligibleForStyleGeneration(corpus)
                        ? AppL10n.string("polishStyles.learn.ready")
                        : AppL10n.format(
                            "polishStyles.learn.remaining",
                            Int64(
                                max(
                                    0,
                                    styleLearningMinimumCharacterCount
                                        - corpus.effectiveCharacterCount
                                )
                            )
                        )
                )
                .font(TypeStyle.caption2)
                .foregroundStyle(
                    isEligibleForStyleGeneration(corpus)
                        ? palette.accent
                        : palette.textTertiary
                )
            }

            Button {
                generateLearnedStyle(from: corpus)
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isGeneratingLearnedStyle {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isActionAvailable ? palette.textOnAccent : palette.textSecondary)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(
                        isGeneratingLearnedStyle
                            ? AppL10n.string("polishStyles.learn.generating")
                            : AppL10n.string("polishStyles.learn.action")
                    )
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(
                    isActionAvailable ? palette.textOnAccent : palette.textSecondary
                )
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    isActionAvailable ? palette.accent : palette.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            .accessibilityIdentifier("polishStyles.learn.generate")

            Text(
                reachedLimit
                    ? AppL10n.string("polishStyles.learn.limit")
                    : AppL10n.string("polishStyles.learn.privacy")
            )
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .surfaceCard()
    }

    private func learnedStyleCard(
        _ pack: PolishStylePack,
        corpus: PolishStyleLearningCorpus
    ) -> some View {
        let isSelected = pack.id == activeID
        let canRegenerate = isEligibleForStyleGeneration(corpus)
            && !isGeneratingLearnedStyle
        let hasInsufficientEvidence = Self.hasInsufficientEvidence(pack.learningMetadata)
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        let actionShape = RoundedRectangle(
            cornerRadius: Radius.medium,
            style: .continuous
        )
        let selectedFillColors = colorScheme == .dark
            ? [
                OSGColor.selectedCardFillLeadingDark,
                OSGColor.selectedCardFillTrailingDark
            ]
            : [
                OSGColor.selectedCardFillLeadingLight,
                OSGColor.selectedCardFillTrailingLight
            ]
        let selectedStroke = colorScheme == .dark
            ? OSGColor.selectedCardStrokeDark
            : OSGColor.selectedCardStrokeLight

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        palette.textPrimary.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: Radius.medium,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.displayName(language: config.uiLanguage))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(
                        hasInsufficientEvidence
                            ? AppL10n.string("polishStyles.learn.lowConfidence")
                            : AppL10n.string("polishStyles.learn.generated.description")
                    )
                        .font(TypeStyle.caption2)
                        .foregroundStyle(
                            hasInsufficientEvidence
                                ? palette.danger
                                : palette.textSecondary
                        )
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
                .disabled(isGeneratingLearnedStyle)
                .accessibilityLabel(Text("polishStyles.edit"))
            }

            if let metadata = pack.learningMetadata {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "clock")
                        Text("polishStyles.learn.generatedAt")
                        Text(
                            metadata.generatedAt,
                            format: .dateTime.year().month().day()
                        )
                    }
                    Text(
                        AppL10n.format(
                            "polishStyles.learn.evidenceSummary",
                            Int64(metadata.asrEffectiveCharacterCount),
                            Int64(metadata.replyExampleCount),
                            Int64(metadata.replyFinalEditCount)
                        )
                    )
                    Text(
                        AppL10n.format(
                            "polishStyles.learn.confidence",
                            Self.confidencePercentage(metadata.confidence)
                        )
                    )
                }
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
            }

            HStack(spacing: Spacing.sm) {
                if isSelected {
                    Label(
                        "polishStyles.learn.selected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(palette.accentMuted, in: actionShape)
                } else {
                    Button {
                        activate(pack)
                    } label: {
                        Label(
                            "polishStyles.learn.select",
                            systemImage: "checkmark.circle"
                        )
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.surfaceElevated, in: actionShape)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    generateLearnedStyle(from: corpus, replacing: pack)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if isGeneratingLearnedStyle {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(
                            isGeneratingLearnedStyle
                                ? "polishStyles.learn.regenerating"
                                : "polishStyles.learn.regenerate"
                        )
                    }
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(
                        canRegenerate
                            ? palette.textPrimary
                            : palette.textTertiary
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(palette.surfaceElevated, in: actionShape)
                }
                .buttonStyle(.plain)
                .disabled(!canRegenerate)
                .accessibilityIdentifier("polishStyles.learn.regenerate")
                .accessibilityValue(Text(pack.id))
            }
        }
        .padding(Spacing.lg)
        .background {
            shape
                .fill(palette.surface)
                .overlay {
                    if isSelected {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: selectedFillColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                shape.stroke(selectedStroke, lineWidth: 0.75)
                            )
                    }
                }
        }
        .clipShape(shape)
        .cardElevation(accented: isSelected)
        .accessibilityIdentifier("polishStyles.learnedStyle.card")
    }

    private func packGridSection(
        title: LocalizedStringKey,
        packs: [PolishStylePack]
    ) -> some View {
        CardSection(title) {
            LazyVGrid(columns: columns, spacing: CardLayoutMetrics.compactItemSpacing) {
                ForEach(packs) { pack in
                    packCard(pack)
                }
            }
        }
    }

    private func packCard(_ pack: PolishStylePack) -> some View {
        let isSelected = pack.id == activeID
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        let selectedFillColors = colorScheme == .dark
            ? [
                OSGColor.selectedCardFillLeadingDark,
                OSGColor.selectedCardFillTrailingDark
            ]
            : [
                OSGColor.selectedCardFillLeadingLight,
                OSGColor.selectedCardFillTrailingLight
            ]
        let selectedStroke = colorScheme == .dark
            ? OSGColor.selectedCardStrokeDark
            : OSGColor.selectedCardStrokeLight
        return ZStack(alignment: .topTrailing) {
            Button {
                activate(pack)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(pack.displayName(language: config.uiLanguage))
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.trailing, 32)
                    Text(descriptionKey(for: pack))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if pack.kind == .builtin {
                    viewingPack = pack
                } else {
                    editingPack = pack
                }
            } label: {
                CatalogCardChrome.editIcon(palette: palette)
            }
            .padding(Spacing.sm)
            .buttonStyle(.plain)
            .disabled(isGeneratingLearnedStyle)
            .accessibilityLabel(Text("polishStyles.edit"))

            if isSelected {
                CatalogCardChrome.checkIcon(palette: palette)
            }
        }
        .background {
            shape
                .fill(palette.surface)
                .overlay {
                    if isSelected {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: selectedFillColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(shape.stroke(selectedStroke, lineWidth: 0.75))
                    }
                }
        }
        .clipShape(shape)
        .cardElevation(accented: isSelected)
        .contextMenu {
            Button("polishStyles.duplicate") {
                duplicate(pack)
            }
            .disabled(isGeneratingLearnedStyle)
            if pack.kind == .user {
                Button("common.delete", role: .destructive) {
                    delete(pack)
                }
                .disabled(isGeneratingLearnedStyle)
            }
        }
    }

    private func generateLearnedStyle(
        from corpus: PolishStyleLearningCorpus,
        replacing existingPack: PolishStylePack? = nil
    ) {
        guard isEligibleForStyleGeneration(corpus),
              !isGeneratingLearnedStyle,
              learnedStyleGenerationTask == nil else { return }
        let generationID = UUID()
        learnedStyleGenerationID = generationID
        isGeneratingLearnedStyle = true
        learnedStyleGenerationTask = Task { @MainActor in
            defer { finishLearnedStyleGeneration(id: generationID) }
            do {
                let generated = try await learnedStyleGenerator(
                    corpus,
                    ClipboardReplyFeedbackStore.shared.learningExamples(),
                    config.uiLanguage
                )
                try Task.checkCancellation()
                guard learnedStyleGenerationID == generationID,
                      editingPack == nil,
                      viewingPack == nil else { return }
                // Always let the user inspect and edit the learned prompt before
                // it is saved, synced, or made active.
                if let existingPack {
                    editingPack = PolishStylePack(
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
                    editingPack = generated
                }
            } catch {
                guard learnedStyleGenerationID == generationID,
                      !Task.isCancelled,
                      !Self.isCancellation(error) else { return }
                errorAlert = PolishStyleErrorAlert(
                    title: AppL10n.string("polishStyles.learn.error.title"),
                    message: localizedLearningError(error)
                )
            }
        }
    }

    private func cancelLearnedStyleGeneration() {
        learnedStyleGenerationTask?.cancel()
        learnedStyleGenerationTask = nil
        learnedStyleGenerationID = nil
        isGeneratingLearnedStyle = false
    }

    private func finishLearnedStyleGeneration(id: UUID) {
        guard learnedStyleGenerationID == id else { return }
        learnedStyleGenerationTask = nil
        learnedStyleGenerationID = nil
        isGeneratingLearnedStyle = false
    }

    private func descriptionKey(for pack: PolishStylePack) -> LocalizedStringKey {
        guard pack.kind == .builtin else { return "polishStyles.custom.description" }
        switch pack.id {
        case "builtin.structured": return "polishStyles.structured.description"
        case "builtin.formal": return "polishStyles.formal.description"
        case "builtin.dating": return "polishStyles.dating.description"
        case "builtin.chat": return "polishStyles.chat.description"
        case "builtin.flex": return "polishStyles.flex.description"
        case "builtin.corp": return "polishStyles.corp.description"
        case "builtin.diba": return "polishStyles.diba.description"
        case "builtin.xhs": return "polishStyles.xhs.description"
        default: return "polishStyles.light.description"
        }
    }

    private func reload() {
        catalog = store.polishStyleCatalog
        activeID = store.activePolishStyleId
    }

    private func activate(_ pack: PolishStylePack) {
        store.setActivePolishStyleId(pack.id)
        activeID = pack.id
        Task {
            try? await AppCloudSync.shared.settingsSyncService.pushLocalIfEnabled()
        }
    }

    private func save(_ pack: PolishStylePack) -> Bool {
        var updatedCatalog = catalog
        do {
            try updatedCatalog.upsert(pack)
            catalog = updatedCatalog
            store.setPolishStyleCatalog(catalog)
            store.setActivePolishStyleId(pack.id)
            activeID = pack.id
            Task {
                try? await PolishStyleCloudSync.shared.pushLocalIfEnabled(catalog)
                try? await AppCloudSync.shared.settingsSyncService.pushLocalIfEnabled()
            }
            return true
        } catch {
            errorAlert = PolishStyleErrorAlert(
                title: AppL10n.string("polishStyles.error.title"),
                message: localized(error)
            )
            return false
        }
    }

    private func duplicate(_ pack: PolishStylePack) {
        guard !isGeneratingLearnedStyle else { return }
        guard catalog.entries.count < PolishStyleLimits.maximumUserPacks else {
            errorAlert = PolishStyleErrorAlert(
                title: AppL10n.string("polishStyles.error.title"),
                message: AppL10n.string("polishStyles.error.limit")
            )
            return
        }
        editingPack = PolishStylePack(
            name: String(
                format: AppL10n.string("polishStyles.copyName"),
                pack.displayName(language: config.uiLanguage)
            ),
            prompt: pack.prompt,
            allowsAddedEmoji: pack.allowsAddedEmoji
        )
    }

    private static func makeDraftPack() -> PolishStylePack {
        PolishStylePack(
            name: "",
            prompt: PolishStylePackCatalog.newUserPromptTemplate
        )
    }

    private func delete(_ pack: PolishStylePack) {
        guard pack.kind == .user, !isGeneratingLearnedStyle else { return }
        catalog.recordDeletion(of: pack.id)
        store.setPolishStyleCatalog(catalog)
        if activeID == pack.id {
            activeID = PolishStylePackCatalog.defaultID
            store.setActivePolishStyleId(activeID)
        }
        Task {
            try? await PolishStyleCloudSync.shared.pushLocalIfEnabled(catalog)
            try? await AppCloudSync.shared.settingsSyncService.pushLocalIfEnabled()
        }
    }

    private func localizedLearningError(_ error: Error) -> String {
        switch error as? PolishStyleLearningError {
        case .insufficientCorpus:
            return AppL10n.string("polishStyles.learn.error.insufficient")
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

    private static func hasInsufficientEvidence(
        _ metadata: PolishStylePack.LearningMetadata?
    ) -> Bool {
        metadata?.evidenceStatus.caseInsensitiveCompare("insufficient") == .orderedSame
    }

    private static func confidencePercentage(_ confidence: Double) -> Int64 {
        Int64((min(max(confidence, 0), 1) * 100).rounded())
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? LLMError) == .cancelled
    }
}

private struct PolishStylePromptDetailSheet: View {
    let pack: PolishStylePack
    let language: AppUILanguage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent {
                    Text(pack.prompt)
                        .font(.body.monospaced())
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .surfaceCard(elevated: false)
                }
            }
            .background(palette.background)
            .navigationTitle(pack.displayName(language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                        .tint(palette.textPrimary)
                }
            }
        }
    }
}

private struct PolishStyleEditorSheet: View {
    let pack: PolishStylePack
    let isNew: Bool
    let onSave: (PolishStylePack) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @State private var name: String
    @State private var prompt: String
    @State private var allowsAddedEmoji: Bool

    init(
        pack: PolishStylePack,
        isNew: Bool,
        onSave: @escaping (PolishStylePack) -> Bool
    ) {
        self.pack = pack
        self.isNew = isNew
        self.onSave = onSave
        _name = State(initialValue: pack.name)
        _prompt = State(initialValue: pack.prompt)
        _allowsAddedEmoji = State(initialValue: pack.allowsAddedEmoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let metadata = pack.learningMetadata {
                    Section {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(
                                Self.hasInsufficientEvidence(metadata)
                                    ? AppL10n.string("polishStyles.learn.lowConfidence")
                                    : AppL10n.string("polishStyles.learn.generated.description")
                            )
                            .font(TypeStyle.caption2)
                            .foregroundStyle(
                                Self.hasInsufficientEvidence(metadata)
                                    ? palette.danger
                                    : palette.textSecondary
                            )
                            Text(
                                AppL10n.format(
                                    "polishStyles.learn.confidence",
                                    Self.confidencePercentage(metadata.confidence)
                                )
                            )
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textTertiary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                        .accessibilityIdentifier("polishStyles.editor.learningEvidence")
                    }
                }
                Section("polishStyles.editor.name") {
                    TextField("polishStyles.editor.namePlaceholder", text: $name)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                }
                Section {
                    Toggle("polishStyles.editor.allowsAddedEmoji", isOn: $allowsAddedEmoji)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                } footer: {
                    Text("polishStyles.editor.allowsAddedEmoji.hint")
                }
                Section {
                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 320)
                        .padding(Spacing.md)
                        .cardListRow(elevated: false)
                        .accessibilityIdentifier("polishStyles.editor.prompt")
                        .onChange(of: prompt) { _, newValue in
                            // Paste-only custom prompts that declare emoji opt-in
                            // should flip the toggle so post-processing keeps them.
                            if !allowsAddedEmoji,
                               PolishStylePack.promptDeclaresAddedEmojiOptIn(newValue) {
                                allowsAddedEmoji = true
                            }
                        }
                } header: {
                    HStack {
                        Text("polishStyles.editor.prompt")
                        Spacer()
                        Text("\(prompt.count)/\(PolishStyleLimits.maximumPromptCharacters)")
                            .foregroundStyle(
                                prompt.count > PolishStyleLimits.maximumPromptCharacters
                                    ? palette.danger
                                    : palette.textTertiary
                            )
                    }
                } footer: {
                    Text("polishStyles.editor.hint")
                }
            }
            .navigationTitle(isNew ? "polishStyles.add" : "polishStyles.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                        .tint(palette.textPrimary)
                        .accessibilityIdentifier("polishStyles.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        let result = PolishStylePack(
                            id: pack.id,
                            name: name,
                            prompt: prompt,
                            allowsAddedEmoji: allowsAddedEmoji
                                || PolishStylePack.promptDeclaresAddedEmojiOptIn(prompt),
                            learningMetadata: pack.learningMetadata,
                            kind: .user,
                            createdAt: pack.createdAt,
                            updatedAt: Date()
                        )
                        if onSave(result) {
                            dismiss()
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.count > PolishStyleLimits.maximumPromptCharacters
                    )
                    .tint(palette.textPrimary)
                    .accessibilityIdentifier("polishStyles.editor.save")
                }
            }
        }
    }

    private static func hasInsufficientEvidence(
        _ metadata: PolishStylePack.LearningMetadata
    ) -> Bool {
        metadata.evidenceStatus.caseInsensitiveCompare("insufficient") == .orderedSame
    }

    private static func confidencePercentage(_ confidence: Double) -> Int64 {
        Int64((min(max(confidence, 0), 1) * 100).rounded())
    }
}
