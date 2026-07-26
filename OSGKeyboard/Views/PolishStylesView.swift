// PolishStylesView.swift
// OSGKeyboard · Main App
//
// Main-app editor for complete polish writing personalities. The keyboard
// reads the selected pack from App Group storage on the next polish request.

import SwiftUI
import OSGKeyboardShared

@MainActor
struct PolishStylesView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared

    @State private var catalog = AppGroupStore().polishStyleCatalog
    @State private var activeID = AppGroupStore().activePolishStyleId
    @State private var editingPack: PolishStylePack?
    @State private var viewingPack: PolishStylePack?
    @State private var showEditor = false
    @State private var errorMessage: String?

    private let store = AppGroupStore()
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    packGridSection(
                        title: "polishStyles.builtin.section",
                        packs: PolishStylePackCatalog.builtins
                    )
                    if !catalog.entries.isEmpty {
                        packGridSection(
                            title: "polishStyles.custom.section",
                            packs: PolishStylePackCatalog.all(userCatalog: catalog)
                                .filter { $0.kind == .user }
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
            }
            .background(palette.background)
            .tabBarScrollBottomPadding()
            .navigationTitle("polishStyles.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingPack = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(catalog.entries.count >= PolishStyleLimits.maximumUserPacks)
                    .accessibilityLabel(Text("polishStyles.add"))
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            PolishStyleEditorSheet(pack: editingPack) { pack in
                save(pack)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: Spacing.md) {
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
                    Image(systemName: iconName(for: pack))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                    Text(pack.displayName(language: config.uiLanguage))
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(descriptionKey(for: pack))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if pack.kind == .builtin {
                    viewingPack = pack
                } else {
                    editingPack = pack
                    showEditor = true
                }
            } label: {
                Image(systemName: pack.kind == .builtin ? "eye" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(palette.background.opacity(0.75), in: Circle())
            }
            .padding(Spacing.sm)
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(pack.kind == .builtin ? "polishStyles.viewPrompt" : "polishStyles.edit")
            )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .background(Color.white, in: Circle())
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
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

    private func iconName(for pack: PolishStylePack) -> String {
        switch pack.id {
        case "builtin.structured": return "list.bullet.rectangle"
        case "builtin.formal": return "briefcase"
        case "builtin.dating": return "heart.text.square"
        case "builtin.chat": return "bubble.left.and.bubble.right"
        case "builtin.light": return "wand.and.sparkles"
        default: return "text.badge.star"
        }
    }

    private func descriptionKey(for pack: PolishStylePack) -> LocalizedStringKey {
        guard pack.kind == .builtin else { return "polishStyles.custom.description" }
        switch pack.id {
        case "builtin.structured": return "polishStyles.structured.description"
        case "builtin.formal": return "polishStyles.formal.description"
        case "builtin.dating": return "polishStyles.dating.description"
        case "builtin.chat": return "polishStyles.chat.description"
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
            prompt: pack.prompt
        )
        showEditor = true
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
                Text(pack.prompt)
                    .font(.body.monospaced())
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .background(
                        palette.surface,
                        in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
                    .padding(Spacing.md)
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
    let pack: PolishStylePack?
    let onSave: (PolishStylePack) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @State private var name: String
    @State private var prompt: String

    init(pack: PolishStylePack?, onSave: @escaping (PolishStylePack) -> Void) {
        self.pack = pack
        self.onSave = onSave
        _name = State(initialValue: pack?.name ?? "")
        _prompt = State(initialValue: pack?.prompt ?? PolishStylePackCatalog.newUserPromptTemplate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("polishStyles.editor.name") {
                    TextField("polishStyles.editor.namePlaceholder", text: $name)
                }
                Section {
                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 320)
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
            .navigationTitle(pack == nil ? "polishStyles.add" : "polishStyles.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        let result = PolishStylePack(
                            id: pack?.id ?? "user.\(UUID().uuidString.lowercased())",
                            name: name,
                            prompt: prompt,
                            kind: .user,
                            createdAt: pack?.createdAt ?? Date()
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
