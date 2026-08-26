// HistoryView.swift
// OSGKeyboard · Main App

import OSGKeyboardShared
import SwiftUI

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
        .toolbar {
            if !store.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(palette.textPrimary)
                    .accessibilityLabel("history.clear.button")
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
                }
            }
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

    // MARK: - Card list

    private var list: some View {
        ScrollView {
            CardPageContent {
                ForEach(store.groupedByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
                        daySectionHeader(day: group.day)

                        LazyVStack(spacing: CardLayoutMetrics.compactItemSpacing) {
                            ForEach(group.items) { entry in
                                historyRow(entry)
                                    .surfaceCard()
                                    .contextMenu {
                                        Button("common.delete", role: .destructive) {
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
    }

    /// Date label + per-day delete, flush with the section card's left/right edges
    /// (CardPageContent gives labels and cards the same horizontal guide).
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
        // CardPageContent owns horizontal padding, so no row-specific
        // compensation is needed to keep the label flush with the cards.
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

    private func delete(_ entry: SpeechHistoryEntry) {
        store.delete(id: entry.id)
    }
}
