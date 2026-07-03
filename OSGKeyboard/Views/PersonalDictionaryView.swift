// PersonalDictionaryView.swift
// OSGKeyboard · Main App
//
// Settings → Personal Dictionary: review, search, delete individual
// entries, or clear the whole dictionary. Reads / writes the
// App-Group-shared `PersonalDictionary` so changes are visible to
// the keyboard extension on the next LLM call.
//
// v0.3.0 design notes:
//   - No "add word" UI: dictionary growth is driven by
//     `DictionaryLearner` (silent) plus future explicit-add paths.
//     The user can re-classify, edit, or delete any entry.
//   - "Clear all" requires confirmation. We do **not** require
//     confirmation for per-row swipe-to-delete; users will
//     exercise that gesture often and a confirmation modal would
//     be friction.
//   - Search filters by substring match on the term and aliases.
//   - Sectioned by `Entry.Category` so the user can scan a
//     technical-names section quickly.

import SwiftUI
import OSGKeyboardShared

@MainActor
struct PersonalDictionaryView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.dismiss) private var dismiss

    @State private var dictionary: PersonalDictionary = AppGroupStore().personalDictionary
    @State private var searchText: String = ""

    private let store = AppGroupStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageHeaderRow(title: "settings.personalDictionary.title") {
                    if !dictionary.entries.isEmpty {
                        PageHeaderConfirmButton(
                            systemImage: "trash",
                            accessibilityLabel: "settings.personalDictionary.clearAll",
                            confirmTitle: "settings.personalDictionary.clearAll.confirmTitle",
                            confirmMessage: "settings.personalDictionary.clearAll.message",
                            confirmActionTitle: "settings.personalDictionary.clearAll.confirm"
                        ) {
                            clearAll()
                        }
                    }
                }

                ZStack {
                    palette.background.ignoresSafeArea()
                    if dictionary.entries.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .background(palette.background)
            .toolbar(.hidden, for: .navigationBar)
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
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .padding(.bottom, 100)
        }
        .searchable(text: $searchText, prompt: "settings.personalDictionary.search.prompt")
    }

    private var introBanner: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            MaterialIcon(name: .bookmark, size: 18)
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.personalDictionary.intro.title")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textPrimary)
                Text("settings.personalDictionary.intro.body")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private func section(for category: PersonalDictionary.Entry.Category, items: [PersonalDictionary.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(LocalizedStringKey(category.labelKey))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry)
                    if index < items.count - 1 {
                        Divider().background(palette.divider)
                    }
                }
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    private func entryRow(_ entry: PersonalDictionary.Entry) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.term)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(entry.source.labelKey))
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
                    if !entry.aliases.isEmpty {
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
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
        .contentShape(Rectangle())
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
            MaterialIcon(name: .bookmark, size: 36)
                .foregroundStyle(palette.textTertiary.opacity(0.5))
            Text("settings.personalDictionary.empty.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
            Text("settings.personalDictionary.empty.body")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
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
        // Group + sort by usageCount desc within each section.
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

    private func delete(_ entry: PersonalDictionary.Entry) {
        dictionary.entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func clearAll() {
        dictionary = .empty
        persist()
    }

    private func persist() {
        dictionary.version += 1
        store.personalDictionary = dictionary
    }
}

#Preview {
    PersonalDictionaryView()
        .environment(\.themePalette, ThemePalette())
}
