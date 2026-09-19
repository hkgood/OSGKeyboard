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

    private let store = AppGroupStore()
    private let pullsCloudStylesOnAppear: Bool
    private let columns = [
        GridItem(.flexible(), spacing: CardLayoutMetrics.compactItemSpacing),
        GridItem(.flexible(), spacing: CardLayoutMetrics.compactItemSpacing)
    ]

    init(
        initialEditingPack: PolishStylePack? = nil,
        pullsCloudStylesOnAppear: Bool = true
    ) {
        _editingPack = State(initialValue: initialEditingPack)
        self.pullsCloudStylesOnAppear = pullsCloudStylesOnAppear
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent {
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
            .navigationTitle(AppL10n.string("polishStyles.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingPack = Self.makeDraftPack()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(palette.textPrimary)
                    .disabled(catalog.entries.count >= PolishStyleLimits.maximumUserPacks)
                    .accessibilityLabel(Text(AppL10n.string("polishStyles.add")))
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
            Button(AppL10n.string("common.done")) { errorAlert = nil }
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
    }

    /// Distilled personal styles belong to the Skills tab and drive AI replies
    /// only, so they never appear here — not even under "My styles". Filtering
    /// by `isPersonalReplyStyle` rather than by "newest learned pack" also keeps
    /// older generations from leaking in as if they were hand-written.
    private var remainingUserPacks: [PolishStylePack] {
        PolishStylePackCatalog.all(userCatalog: catalog)
            .filter { $0.kind == .user && !PolishStylePackCatalog.isPersonalReplyStyle($0) }
    }

    private func packGridSection(
        title: String,
        packs: [PolishStylePack]
    ) -> some View {
        CardSection(title: AppL10n.string(title)) {
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
            .accessibilityLabel(Text(AppL10n.string("polishStyles.edit")))

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
            Button(AppL10n.string("polishStyles.duplicate")) {
                duplicate(pack)
            }
            if pack.kind == .user {
                Button(AppL10n.string("common.delete"), role: .destructive) {
                    delete(pack)
                }
            }
        }
    }

    private func descriptionKey(for pack: PolishStylePack) -> String {
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
        guard pack.kind == .user else { return }
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
                    Button(AppL10n.string("common.done")) { dismiss() }
                        .tint(palette.textPrimary)
                }
            }
        }
    }
}

/// Shared with `PersonalReplyStyleSection`: a generated personal style is
/// reviewed in the same editor before it is saved or enabled.
struct PolishStyleEditorSheet: View {
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
                                    ? AppL10n.string("personalReplyStyle.lowConfidence")
                                    : AppL10n.string("personalReplyStyle.generated.description")
                            )
                            .font(TypeStyle.caption2)
                            .foregroundStyle(
                                Self.hasInsufficientEvidence(metadata)
                                    ? palette.danger
                                    : palette.textSecondary
                            )
                            Text(
                                AppL10n.format(
                                    "personalReplyStyle.confidence",
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
                Section(AppL10n.string("polishStyles.editor.name")) {
                    TextField(AppL10n.string("polishStyles.editor.namePlaceholder"), text: $name)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                }
                Section {
                    Toggle(AppL10n.string("polishStyles.editor.allowsAddedEmoji"), isOn: $allowsAddedEmoji)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                } footer: {
                    Text(AppL10n.string("polishStyles.editor.allowsAddedEmoji.hint"))
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
                        Text(AppL10n.string("polishStyles.editor.prompt"))
                        Spacer()
                        Text("\(prompt.count)/\(PolishStyleLimits.maximumPromptCharacters)")
                            .foregroundStyle(
                                prompt.count > PolishStyleLimits.maximumPromptCharacters
                                    ? palette.danger
                                    : palette.textTertiary
                            )
                    }
                } footer: {
                    Text(AppL10n.string("polishStyles.editor.hint"))
                }
            }
            .navigationTitle(isNew ? "polishStyles.add" : "polishStyles.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppL10n.string("common.cancel")) { dismiss() }
                        .tint(palette.textPrimary)
                        .accessibilityIdentifier("polishStyles.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("common.save")) {
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
