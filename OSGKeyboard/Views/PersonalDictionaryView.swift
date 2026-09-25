// PersonalDictionaryView.swift
// OSGKeyboard · Main App
//
// Personal Dictionary tab: review, search, add, edit, delete
// individual entries, or clear the whole dictionary. Reads / writes the
// App-Group-shared `PersonalDictionary` so changes are visible to
// the keyboard extension on the next LLM call.

import OSGKeyboardShared
import SwiftUI

@MainActor
struct PersonalDictionaryView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared

    @State private var dictionary: PersonalDictionary = AppGroupStore().personalDictionary
    @State private var searchText: String = ""
    @State private var showClearAllConfirmation = false
    @State private var showEntrySheet = false
    @State private var editingEntry: PersonalDictionary.Entry?
    @State private var generatingAliasEntryIDs: Set<UUID> = []

    private let store = AppGroupStore()
    private let dictionaryEntryService = PersonalDictionaryEntryService()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            if dictionary.entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(palette.background)
        .navigationTitle(AppL10n.string("settings.personalDictionary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !dictionary.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(palette.textPrimary)
                    .accessibilityLabel(AppL10n.string("settings.personalDictionary.clearAll"))
                    .confirmationDialog(
                        AppL10n.string("settings.personalDictionary.clearAll.confirmTitle"),
                        isPresented: $showClearAllConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(AppL10n.string("settings.personalDictionary.clearAll.confirm"), role: .destructive) {
                            clearAll()
                        }
                        Button(AppL10n.string("common.cancel"), role: .cancel) {}
                    } message: {
                        Text(AppL10n.string("settings.personalDictionary.clearAll.message"))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingEntry = nil
                    showEntrySheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(palette.textPrimary)
                .accessibilityLabel(AppL10n.string("settings.personalDictionary.add.title"))
            }
        }
        .sheet(isPresented: $showEntrySheet) {
            PersonalDictionaryEntrySheet(
                initialTerm: editingEntry?.term ?? "",
                isEditing: editingEntry != nil
            ) { term in
                saveEntry(
                    term: term,
                    editingID: editingEntry?.id,
                    source: editingEntry?.source ?? .manual
                )
            }
        }
        .task {
            reloadFromStore()
            await PersonalDictionaryCloudSync.shared.pullAndMergeIfEnabled()
            reloadFromStore()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)
        ) { _ in
            reloadFromStore()
        }
    }

    // MARK: - Card list

    private var list: some View {
        ScrollView {
            CardPageContent(topPadding: Spacing.lg) {
                ForEach(filteredSections, id: \.0) { category, items in
                    CardSection(
                        title: SharedL10n.string(category.labelKey, language: config.uiLanguage)
                    ) {
                        LazyVStack(spacing: CardLayoutMetrics.compactItemSpacing) {
                            ForEach(items) { entry in
                                entryRow(entry)
                                    .surfaceCard()
                                    .contextMenu {
                                        Button(AppL10n.string("common.delete"), role: .destructive) {
                                            delete(entry)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .tabBarScrollBottomPadding()
        }
        .scrollClipDisabled()
        .background(palette.background)
        // CardPageContent keeps the search results and their section labels
        // on the same horizontal guide while preserving top breathing room.
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "settings.personalDictionary.search.prompt"
        )
    }

    private func entryRow(_ entry: PersonalDictionary.Entry) -> some View {
        Button {
            editingEntry = entry
            showEntrySheet = true
        } label: {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.term)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(SharedL10n.string(entry.source.labelKey, language: config.uiLanguage))
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textTertiary)
                        if generatingAliasEntryIDs.contains(entry.id) {
                            Text("·")
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                            Text(AppL10n.string("settings.personalDictionary.aliases.generating"))
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                        } else if !entry.aliases.isEmpty {
                            Text("·")
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                            Text(entry.aliases.joined(separator: " / "))
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(palette.textTertiary.opacity(0.5))
            Text(AppL10n.string("settings.personalDictionary.empty.title"))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
            Text(AppL10n.string("settings.personalDictionary.empty.body"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Button {
                editingEntry = nil
                showEntrySheet = true
            } label: {
                Text(AppL10n.string("settings.personalDictionary.add.title"))
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .padding(.top, Spacing.sm)
        }
        // 内容按自身高度居中，再上移抵消 large title 占用的顶部空间，
        // 让空状态在整屏视觉上真正垂直居中。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 72)
    }

    // MARK: - Derived data

    private var filteredSections: [(PersonalDictionary.Entry.Category, [PersonalDictionary.Entry])] {
        let filtered: [PersonalDictionary.Entry]
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filtered = dictionary.entries
        } else {
            let needle = trimmed.lowercased()
            filtered = dictionary.entries.filter { entry in
                if entry.term.lowercased().contains(needle) { return true }
                return entry.aliases.contains(where: { $0.lowercased().contains(needle) })
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

    // MARK: - Mutations

    private func saveEntry(
        term: String,
        editingID: UUID?,
        source: PersonalDictionary.Entry.Source
    ) {
        guard let saved = dictionaryEntryService.saveEntry(
            term: term,
            existingID: editingID,
            source: source
        ) else {
            return
        }
        dictionary = saved.dictionary
        if saved.shouldGenerateAliases {
            generatingAliasEntryIDs.insert(saved.entryID)
        }
        Task {
            dictionary = await dictionaryEntryService.finishSaving(saved)
            generatingAliasEntryIDs.remove(saved.entryID)
        }
    }

    private func delete(_ entry: PersonalDictionary.Entry) {
        dictionary.recordDeletion(of: entry.id)
        generatingAliasEntryIDs.remove(entry.id)
        persist()
    }

    private func clearAll() {
        dictionary.recordClearAll()
        generatingAliasEntryIDs = []
        persist()
    }

    private func persist() {
        dictionary.version += 1
        store.setPersonalDictionary(dictionary)
        Task {
            try? await PersonalDictionaryCloudSync.shared.pushLocalIfEnabled(dictionary)
        }
    }

    private func reloadFromStore() {
        dictionary = store.personalDictionary
    }
}

#if DEBUG
#Preview {
    ThemedRoot {
        PersonalDictionaryView()
    }
}
#endif
