// MacPolishStylesView.swift
// OSGKeyboard · Mac
//
// macOS counterpart of the iOS polish-styles tab. Both surfaces edit the same
// Shared model and iCloud payload.

import SwiftUI

struct MacPolishStylesView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette

    @State private var editingPack: PolishStylePack?
    @State private var showEditor = false
    @State private var errorMessage: String?

    private var lang: AppUILanguage { viewModel.config.uiLanguage }
    private var store: AppGroupStore { AppGroupStore(defaults: viewModel.defaults) }
    private var catalog: PolishStyleCatalog {
        _ = viewModel.polishStylesRevision
        return store.polishStyleCatalog
    }
    private var activeID: String {
        _ = viewModel.polishStylesRevision
        return store.activePolishStyleId
    }

    var body: some View {
        VStack(spacing: 0) {
            MacPageHeader(
                title: MacL10n.string("mac.section.styles", language: lang),
                subtitle: MacL10n.string("mac.styles.subtitle", language: lang)
            ) {
                Button {
                    editingPack = nil
                    showEditor = true
                } label: {
                    Label(
                        MacL10n.string("mac.styles.add", language: lang),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(catalog.entries.count >= PolishStyleLimits.maximumUserPacks)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    styleSection(
                        title: MacL10n.string("mac.styles.builtin", language: lang),
                        packs: PolishStylePackCatalog.builtins
                    )
                    if !catalog.entries.isEmpty {
                        styleSection(
                            title: MacL10n.string("mac.styles.custom", language: lang),
                            packs: catalog.entries
                        )
                    }
                }
                .padding(.horizontal, MacMetrics.pageHorizontalInset)
                .padding(.bottom, Spacing.xl)
            }
        }
        .background(palette.background)
        .sheet(isPresented: $showEditor) {
            MacPolishStyleEditor(pack: editingPack, language: lang) { pack in
                save(pack)
            }
        }
        .alert(
            MacL10n.string("mac.styles.error", language: lang),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(MacL10n.string("mac.done", language: lang)) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await MacICloudSyncBootstrap.polishStyleSync.pullAndMergeIfEnabled()
            viewModel.refreshPolishStyles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .polishStylesDidSyncFromCloud)) { _ in
            viewModel.refreshPolishStyles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            viewModel.refreshPolishStyles()
        }
    }

    private func styleSection(title: String, packs: [PolishStylePack]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(MacSettingsType.sectionTitle)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            MacCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(packs) { pack in
                        styleRow(pack)
                        if pack.id != packs.last?.id {
                            Divider().background(palette.divider)
                        }
                    }
                }
            }
        }
    }

    private func styleRow(_ pack: PolishStylePack) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                activate(pack)
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: pack.id == activeID ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(pack.id == activeID ? palette.accent : palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.displayName(language: lang))
                            .font(TypeStyle.body)
                            .foregroundStyle(palette.textPrimary)
                        Text(subtitle(for: pack))
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editingPack = PolishStylePack(
                    name: "\(pack.displayName(language: lang)) \(MacL10n.string("mac.styles.copy", language: lang))",
                    prompt: pack.prompt
                )
                showEditor = true
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)

            if pack.kind == .user {
                Button {
                    editingPack = pack
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    delete(pack)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func subtitle(for pack: PolishStylePack) -> String {
        if pack.kind == .user {
            return MacL10n.string("mac.styles.customDescription", language: lang)
        }
        return MacL10n.string("mac.styles.\(pack.id.dropFirst("builtin.".count))", language: lang)
    }

    private func activate(_ pack: PolishStylePack) {
        store.setActivePolishStyleId(pack.id)
        viewModel.refreshPolishStyles()
        Task {
            try? await MacICloudSyncBootstrap.settingsSync.pushLocalIfEnabled()
        }
    }

    private func save(_ pack: PolishStylePack) {
        var updated = catalog
        do {
            try updated.upsert(pack)
            store.setPolishStyleCatalog(updated)
            store.setActivePolishStyleId(pack.id)
            viewModel.refreshPolishStyles()
            Task {
                try? await MacICloudSyncBootstrap.polishStyleSync.pushLocalIfEnabled(updated)
                try? await MacICloudSyncBootstrap.settingsSync.pushLocalIfEnabled()
            }
        } catch {
            errorMessage = MacL10n.string("mac.styles.validation", language: lang)
        }
    }

    private func delete(_ pack: PolishStylePack) {
        var updated = catalog
        updated.recordDeletion(of: pack.id)
        store.setPolishStyleCatalog(updated)
        if activeID == pack.id {
            store.setActivePolishStyleId(PolishStylePackCatalog.defaultID)
        }
        viewModel.refreshPolishStyles()
        Task {
            try? await MacICloudSyncBootstrap.polishStyleSync.pushLocalIfEnabled(updated)
            try? await MacICloudSyncBootstrap.settingsSync.pushLocalIfEnabled()
        }
    }
}

private struct MacPolishStyleEditor: View {
    let pack: PolishStylePack?
    let language: AppUILanguage
    let onSave: (PolishStylePack) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @State private var name: String
    @State private var prompt: String

    init(
        pack: PolishStylePack?,
        language: AppUILanguage,
        onSave: @escaping (PolishStylePack) -> Void
    ) {
        self.pack = pack
        self.language = language
        self.onSave = onSave
        _name = State(initialValue: pack?.name ?? "")
        _prompt = State(initialValue: pack?.prompt ?? PolishStylePackCatalog.newUserPromptTemplate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(MacL10n.string(pack == nil ? "mac.styles.add" : "mac.styles.edit", language: language))
                .font(TypeStyle.title2)
            TextField(MacL10n.string("mac.styles.name", language: language), text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text(MacL10n.string("mac.styles.prompt", language: language))
                    .font(MacSettingsType.sectionTitle)
                Spacer()
                Text("\(prompt.count)/\(PolishStyleLimits.maximumPromptCharacters)")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(
                        prompt.count > PolishStyleLimits.maximumPromptCharacters
                            ? palette.danger
                            : palette.textTertiary
                    )
            }
            TextEditor(text: $prompt)
                .font(.body.monospaced())
                .frame(minHeight: 360)
                .padding(4)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium)
                        .stroke(palette.divider, lineWidth: 1)
                )
            Text(MacL10n.string("mac.styles.hint", language: language))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
            HStack {
                Spacer()
                Button(MacL10n.string("mac.cancel", language: language)) { dismiss() }
                Button(MacL10n.string("mac.save", language: language)) {
                    onSave(
                        PolishStylePack(
                            id: pack?.id ?? "user.\(UUID().uuidString.lowercased())",
                            name: name,
                            prompt: prompt,
                            kind: .user,
                            createdAt: pack?.createdAt ?? Date()
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || prompt.count > PolishStyleLimits.maximumPromptCharacters
                )
            }
        }
        .padding(Spacing.xl)
        .frame(width: 680, height: 590)
        .background(palette.background)
    }
}
