// HistoryView.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct HistoryView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var store = SpeechHistoryStore.shared

    @State private var showClearConfirmation = false
    @State private var showDeleteDayConfirmation = false
    @State private var dayPendingDelete: Date?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            if store.entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(palette.background)
        .navigationTitle("history.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
        .toolbar {
            if !store.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("history.clear.button")
                }
            }
        }
        .confirmationDialog(
            "history.clear.title",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("history.clear.confirm", role: .destructive) {
                store.clearAll()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("history.clear.message")
        }
        .confirmationDialog(
            "history.clearDay.title",
            isPresented: $showDeleteDayConfirmation,
            titleVisibility: .visible
        ) {
            Button("history.clearDay.confirm", role: .destructive) {
                if let day = dayPendingDelete {
                    store.deleteEntries(on: day)
                }
                dayPendingDelete = nil
            }
            Button("common.cancel", role: .cancel) {
                dayPendingDelete = nil
            }
        } message: {
            Text("history.clearDay.message")
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(store.groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { entry in
                        historyRow(entry)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(palette.surface)
                            .listRowSeparatorTint(palette.divider)
                    }
                    .onDelete { offsets in
                        delete(items: group.items, at: offsets)
                    }
                } header: {
                    daySectionHeader(day: group.day)
                }
                .listSectionMargins(.horizontal, Spacing.lg)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.lg)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .contentMargins(.top, Spacing.md, for: .scrollContent)
        .tabBarListScrollBottomMargin()
    }

    /// Date label + per-day delete, flush with the section card's left/right edges
    /// (Settings section labels share the same edge; system List headers inset further).
    private func daySectionHeader(day: Date) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(Self.dayFormatter.string(from: day))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            Spacer(minLength: 0)

            Button {
                dayPendingDelete = day
                showDeleteDayConfirmation = true
            } label: {
                Text("common.delete")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("history.clearDay.button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Cancel the default List section-header content inset so the label
        // lines up with the card's left edge (rows use leading: 0).
        .padding(.horizontal, -SettingsListMetrics.rowHorizontalPadding)
        .textCase(nil)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Spacer()
            MaterialIcon(name: .menuBook, size: 36)
                .foregroundStyle(palette.textTertiary.opacity(0.5))
            Text("history.empty")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }

    private func historyRow(_ entry: SpeechHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Text(Self.timeFormatter.string(from: entry.createdAt))
                    .monospacedDigit()
                if entry.source == .ai {
                    Text("AI")
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                }
            }
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textTertiary)
            Text(entry.text)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mutations

    private func delete(items: [SpeechHistoryEntry], at offsets: IndexSet) {
        for index in offsets {
            store.delete(id: items[index].id)
        }
    }
}
