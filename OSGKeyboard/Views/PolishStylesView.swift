// PolishStylesView.swift
// OSGKeyboard · Main App
//
// Main-app editor for complete polish writing personalities. The keyboard
// reads the selected pack from App Group storage on the next polish request.

import OSGKeyboardShared
import SwiftUI

@MainActor
struct PolishStylesView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared

    @State private var catalog = AppGroupStore().polishStyleCatalog
    @State private var activeID = AppGroupStore().activePolishStyleId
    /// Drives the editor sheet via `sheet(item:)` so create/edit always
    /// receives a concrete pack (avoids `isPresented` + nil race showing defaults).
    @State private var editingPack: PolishStylePack?
    @State private var viewingPack: PolishStylePack?
    @State private var errorMessage: String?

    private let store = AppGroupStore()
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent(spacing: Spacing.xl) {
                    packGridSection(
                        title: "polishStyles.builtin.section",
                        packs: PolishStylePackCatalog.BuiltinStyleGroup.practical.packs
                    )
                    packGridSection(
                        title: "polishStyles.fun.section",
                        packs: PolishStylePackCatalog.BuiltinStyleGroup.fun.packs
                    )
                    if !catalog.entries.isEmpty {
                        packGridSection(
                            title: "polishStyles.custom.section",
                            packs: PolishStylePackCatalog.all(userCatalog: catalog)
                                .filter { $0.kind == .user }
                        )
                    }
                }
                .tabBarScrollBottomPadding()
            }
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
                    .disabled(catalog.entries.count >= PolishStyleLimits.maximumUserPacks)
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
            Text("polishStyles.error.title"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("common.done") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            reload()
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

    private func packGridSection(
        title: LocalizedStringKey,
        packs: [PolishStylePack]
    ) -> some View {
        CardSection(title) {
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(packs) { pack in
                    packCard(pack)
                }
            }
        }
    }

    private func packCard(_ pack: PolishStylePack) -> some View {
        let isSelected = pack.id == activeID
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
            .accessibilityLabel(Text("polishStyles.edit"))

            if isSelected {
                CatalogCardChrome.checkIcon(palette: palette)
            }
        }
        .background(
            isSelected ? palette.accentMuted : palette.surface,
            in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(
                    isSelected ? palette.accent : palette.divider,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .contextMenu {
            Button("polishStyles.duplicate") {
                duplicate(pack)
            }
            if pack.kind == .user {
                Button("common.delete", role: .destructive) {
                    delete(pack)
                }
            }
        }
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

    private func save(_ pack: PolishStylePack) {
        do {
            try catalog.upsert(pack)
            store.setPolishStyleCatalog(catalog)
            store.setActivePolishStyleId(pack.id)
            activeID = pack.id
            Task {
                try? await PolishStyleCloudSync.shared.pushLocalIfEnabled(catalog)
                try? await AppCloudSync.shared.settingsSyncService.pushLocalIfEnabled()
            }
        } catch {
            errorMessage = localized(error)
        }
    }

    private func duplicate(_ pack: PolishStylePack) {
        guard catalog.entries.count < PolishStyleLimits.maximumUserPacks else {
            errorMessage = AppL10n.string("polishStyles.error.limit")
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
                        .surfaceCard()
                }
            }
            .background(palette.background)
            .navigationTitle(pack.displayName(language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }
}

private struct PolishStyleEditorSheet: View {
    let pack: PolishStylePack
    let isNew: Bool
    let onSave: (PolishStylePack) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @State private var name: String
    @State private var prompt: String
    @State private var allowsAddedEmoji: Bool

    init(
        pack: PolishStylePack,
        isNew: Bool,
        onSave: @escaping (PolishStylePack) -> Void
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
                Section("polishStyles.editor.name") {
                    TextField("polishStyles.editor.namePlaceholder", text: $name)
                }
                Section {
                    Toggle("polishStyles.editor.allowsAddedEmoji", isOn: $allowsAddedEmoji)
                } footer: {
                    Text("polishStyles.editor.allowsAddedEmoji.hint")
                }
                Section {
                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 320)
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        let result = PolishStylePack(
                            id: pack.id,
                            name: name,
                            prompt: prompt,
                            allowsAddedEmoji: allowsAddedEmoji
                                || PolishStylePack.promptDeclaresAddedEmojiOptIn(prompt),
                            kind: .user,
                            createdAt: pack.createdAt
                        )
                        onSave(result)
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.count > PolishStyleLimits.maximumPromptCharacters
                    )
                }
            }
        }
    }
}
