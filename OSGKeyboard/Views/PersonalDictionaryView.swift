// PersonalDictionaryView.swift
// OSGKeyboard · Main App
//
// Personal Dictionary tab: review, search, add, edit, delete
// individual entries, or clear the whole dictionary. Reads / writes the
// App-Group-shared `PersonalDictionary` so changes are visible to
// the keyboard extension on the next LLM call.

import SwiftUI
import OSGKeyboardShared

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
    private let aliasGenerator = DictionaryAliasGenerator()

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if dictionary.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(palette.background)
            .navigationTitle("settings.personalDictionary.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !dictionary.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showClearAllConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
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
                            Text("settings.personalDictionary.clearAll.message")
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
                    .accessibilityLabel(AppL10n.string("settings.personalDictionary.add.title"))
                }
            }
        }
        .sheet(isPresented: $showEntrySheet) {
            PersonalDictionaryEntrySheet(
                initialTerm: editingEntry?.term ?? "",
                isEditing: editingEntry != nil
            ) { term in
                saveManualEntry(term: term, editingID: editingEntry?.id)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                introBanner
                ForEach(filteredSections, id: \.0) { category, items in
                    section(for: category, items: items)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .tabBarScrollBottomPadding()
        }
        .searchable(text: $searchText, prompt: "settings.personalDictionary.search.prompt")
    }

    private var introBanner: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("settings.personalDictionary.intro.title")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textPrimary)
            Text("settings.personalDictionary.intro.body")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private func section(for _: PersonalDictionary.Entry.Category, items: [PersonalDictionary.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry)
                    if index < items.count - 1 {
                        Divider().background(palette.divider)
                    }
                }
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
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
                        if entry.usageCount > 1 {
                            Text("·")
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                            Text("settings.personalDictionary.usageCount \(entry.usageCount)")
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                        }
                        if generatingAliasEntryIDs.contains(entry.id) {
                            Text("·")
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                            Text("settings.personalDictionary.aliases.generating")
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
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("common.delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Spacer()
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(palette.textTertiary.opacity(0.5))
            Text("settings.personalDictionary.empty.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
            Text("settings.personalDictionary.empty.body")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Button {
                editingEntry = nil
                showEntrySheet = true
            } label: {
                Text("settings.personalDictionary.add.title")
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .padding(.top, Spacing.sm)
            Spacer()
        }
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

    private func saveManualEntry(term: String, editingID: UUID?) {
        let previousTerm = editingID.flatMap { id in
            dictionary.entries.first(where: { $0.id == id })?.term
        }
        let termChanged = previousTerm.map {
            $0.caseInsensitiveCompare(term) != .orderedSame
        } ?? true

        guard dictionary.upsertManual(term: term, existingID: editingID) != nil else { return }
        persist()

        guard let saved = dictionary.entry(matchingTerm: term) else { return }
        let shouldGenerate = saved.source == .manual && (editingID == nil || termChanged)
        if shouldGenerate {
            generateAliases(for: saved.id, term: saved.term)
        }
    }

    private func generateAliases(for entryID: UUID, term: String) {
        generatingAliasEntryIDs.insert(entryID)
        Task {
            let aliases = await aliasGenerator.generateAliases(for: term)
            generatingAliasEntryIDs.remove(entryID)
            guard !aliases.isEmpty else { return }
            dictionary.updateAliases(for: entryID, aliases: aliases)
            persist()
        }
    }

    private func delete(_ entry: PersonalDictionary.Entry) {
        dictionary.entries.removeAll { $0.id == entry.id }
        generatingAliasEntryIDs.remove(entry.id)
        persist()
    }

    private func clearAll() {
        dictionary = .empty
        generatingAliasEntryIDs = []
        persist()
    }

    private func persist() {
        dictionary.version += 1
        store.setPersonalDictionary(dictionary)
    }
}

#if DEBUG
#Preview {
    ThemedRoot {
        PersonalDictionaryView()
    }
}
#endif
