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
    @State private var viewingPack: PolishStylePack?
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
    /// At the default window (~540pt content), ~170pt min yields 3 columns;
    /// narrower → 2, wider → 4+. Cards stretch equally (no max width).
    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: MacMetrics.polishStyleCardMinWidth),
                spacing: Spacing.md,
                alignment: .top
            ),
        ]
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
                .buttonStyle(MacHeaderActionButtonStyle())
                .disabled(catalog.entries.count >= PolishStyleLimits.maximumUserPacks)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    styleSection(
                        title: MacL10n.string("mac.styles.builtin", language: lang),
                        packs: PolishStylePackCatalog.BuiltinStyleGroup.practical.packs
                    )
                    styleSection(
                        title: MacL10n.string("mac.styles.fun", language: lang),
                        packs: PolishStylePackCatalog.BuiltinStyleGroup.fun.packs
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
        .sheet(item: $viewingPack) { pack in
            MacPolishStylePromptDetailSheet(pack: pack, language: lang)
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

            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
                ForEach(packs) { pack in
                    styleCard(pack)
                }
            }
        }
    }

    private func styleCard(_ pack: PolishStylePack) -> some View {
        MacPolishStyleCard(
            name: pack.displayName(language: lang),
            subtitle: subtitle(for: pack),
            isSelected: pack.id == activeID,
            isUserStyle: pack.kind == .user,
            language: lang,
            activate: {
                activate(pack)
            },
            // Builtin → view prompt; custom → edit (matches iOS).
            primaryAction: {
                if pack.kind == .builtin {
                    viewingPack = pack
                } else {
                    editingPack = pack
                    showEditor = true
                }
            },
            duplicate: {
                editingPack = PolishStylePack(
                    name: "\(pack.displayName(language: lang)) \(MacL10n.string("mac.styles.copy", language: lang))",
                    prompt: pack.prompt
                )
                showEditor = true
            },
            delete: {
                delete(pack)
            }
        )
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

private struct MacPolishStyleCard: View {
    let name: String
    let subtitle: String
    let isSelected: Bool
    let isUserStyle: Bool
    let language: AppUILanguage
    let activate: () -> Void
    let primaryAction: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: activate) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(name)
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.trailing, 32)

                    Text(subtitle)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                .padding(Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Builtin: eye → view prompt; custom: pencil → edit.
            Button(action: primaryAction) {
                Image(systemName: isUserStyle ? "pencil" : "eye")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(palette.background.opacity(isHovering ? 0.9 : 0.72), in: Circle())
            }
            .padding(Spacing.sm)
            .buttonStyle(.plain)
            .accessibilityLabel(
                MacL10n.string(
                    isUserStyle ? "mac.styles.edit" : "mac.styles.viewPrompt",
                    language: language
                )
            )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .background(palette.surface, in: Circle())
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
        }
        .background(
            isSelected ? palette.accentMuted : palette.surface,
            in: shape
        )
        .overlay(
            shape.stroke(
                isSelected ? palette.accent : hoverBorder,
                lineWidth: isSelected ? 1.5 : 0.5
            )
        )
        .clipShape(shape)
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(Motion.quick, value: isHovering)
        .animation(Motion.quick, value: isSelected)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(MacL10n.string("mac.styles.copy", language: language), action: duplicate)
            if isUserStyle {
                Button(MacL10n.string("mac.delete", language: language), role: .destructive, action: delete)
            }
        }
    }

    private var hoverBorder: Color {
        isHovering ? palette.dividerStrong : palette.divider
    }
}

/// Read-only prompt viewer for built-in styles (mirrors iOS).
private struct MacPolishStylePromptDetailSheet: View {
    let pack: PolishStylePack
    let language: AppUILanguage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(pack.displayName(language: language))
                    .font(TypeStyle.title2)
                Spacer()
                Button(MacL10n.string("mac.done", language: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(pack.prompt)
                    .font(.body.monospaced())
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .background(
                        palette.surface,
                        in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    )
            }
        }
        .padding(Spacing.xl)
        .frame(width: 680, height: 520)
        .background(palette.background)
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
