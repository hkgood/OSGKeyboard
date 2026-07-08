// MacDictionaryView.swift
// OSGKeyboard · Mac
//
// Personal dictionary synced via iCloud KVS with the iOS app. Read-only on
// the desktop (words are authored on iPhone / iPad): grouped cards (native
// `Form`) with search, matching the Settings and History card style.

import SwiftUI

struct MacDictionaryView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette
    @State private var query = ""
    @State private var entryPendingDeletion: PersonalDictionary.Entry?

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    private var entries: [PersonalDictionary.Entry] {
        _ = viewModel.dictionaryRevision
        return AppGroupStore(defaults: viewModel.defaults).personalDictionary.entries
    }

    /// Entries filtered by the search field, grouped by category and sorted
    /// (most-used first) — mirrors the iOS Personal Dictionary tab.
    private var sections: [(category: PersonalDictionary.Entry.Category, items: [PersonalDictionary.Entry])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [PersonalDictionary.Entry]
        if trimmed.isEmpty {
            filtered = entries
        } else {
            filtered = entries.filter { entry in
                entry.term.lowercased().contains(trimmed)
                    || entry.aliases.contains { $0.lowercased().contains(trimmed) }
            }
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.category })
        return PersonalDictionary.Entry.Category.allCases.compactMap { category in
            guard let bucket = grouped[category], !bucket.isEmpty else { return nil }
            let sorted = bucket.sorted {
                if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
                return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
            }
            return (category, sorted)
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                form
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .task {
            await MacICloudSyncBootstrap.dictionarySync.pullAndMergeIfEnabled()
            viewModel.refreshDictionaryFromCloud()
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
            viewModel.refreshDictionaryFromCloud()
        }
    }

    // MARK: - Grouped cards

    private var form: some View {
        Form {
            if sections.isEmpty {
                Section {
                    Text(MacL10n.string("mac.dict.noMatch", language: lang))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ForEach(sections, id: \.category) { section in
                    Section(MacL10n.string(section.category.labelKey, language: lang)) {
                        ForEach(section.items) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .safeAreaInset(edge: .top, spacing: 0) { centeredSearchField }
        .confirmationDialog(
            MacL10n.string("mac.dict.deleteTitle", language: lang),
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            Button(MacL10n.string("mac.delete", language: lang), role: .destructive) {
                if let entry = entryPendingDeletion { delete(entry) }
                entryPendingDeletion = nil
            }
            Button(MacL10n.string("mac.cancel", language: lang), role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            Text(MacL10n.string("mac.dict.deleteMessage", language: lang))
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )
    }

    private var centeredSearchField: some View {
        HStack {
            Spacer()
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.textTertiary)
                TextField(MacL10n.string("mac.dict.search", language: lang), text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 7)
            .frame(width: 240)
            .macGlassSurface(in: Capsule(), fillOpacity: 0.72)
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .background(palette.background)
    }

    private func row(_ entry: PersonalDictionary.Entry) -> some View {
        MacDictionaryRow(
            entry: entry,
            subtitle: subtitle(for: entry),
            language: lang,
            copy: { viewModel.copyToClipboard(entry.term) },
            delete: { entryPendingDeletion = entry }
        )
    }

    /// "Manual · ×3 · k8s / kube" — same metadata line as iOS.
    private func subtitle(for entry: PersonalDictionary.Entry) -> String? {
        var parts: [String] = [MacL10n.string(entry.source.labelKey, language: lang)]
        if entry.usageCount > 1 {
            parts.append("×\(entry.usageCount)")
        }
        if !entry.aliases.isEmpty {
            parts.append(entry.aliases.joined(separator: " / "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 34))
                .foregroundStyle(palette.textTertiary.opacity(0.6))
            Text(MacL10n.string("mac.dict.empty", language: lang))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
            Text(MacL10n.string("mac.dict.emptyBody", language: lang))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.xl)
    }

    private func delete(_ entry: PersonalDictionary.Entry) {
        let store = AppGroupStore(defaults: viewModel.defaults)
        store.deletePersonalDictionaryEntry(id: entry.id)
        viewModel.refreshDictionaryFromCloud()
        Task {
            try? await MacICloudSyncBootstrap.dictionarySync.pushLocalIfEnabled(store.personalDictionary)
        }
    }
}

private struct MacDictionaryRow: View {
    let entry: PersonalDictionary.Entry
    let subtitle: String?
    let language: AppUILanguage
    let copy: () -> Void
    let delete: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.term)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.sm)
            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.textTertiary)
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel(MacL10n.string("mac.delete", language: language))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: copy) {
                Label(MacL10n.string("mac.copy", language: language), systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: delete) {
                Label(MacL10n.string("mac.delete", language: language), systemImage: "trash")
            }
        }
    }
}
