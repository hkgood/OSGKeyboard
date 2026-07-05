// HistoryView.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct HistoryView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var store = SpeechHistoryStore.shared

    @State private var showClearConfirmation = false

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
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if store.entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                            ForEach(store.groupedByDay, id: \.day) { group in
                                daySection(day: group.day, items: group.items)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .tabBarScrollBottomPadding()
                    }
                }
            }
            .background(palette.background)
            .navigationTitle("history.title")
            .navigationBarTitleDisplayMode(.large)
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
        }
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

    private func daySection(day: Date, items: [SpeechHistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(Self.dayFormatter.string(from: day))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    historyRow(entry)
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

    private func historyRow(_ entry: SpeechHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(Self.timeFormatter.string(from: entry.createdAt))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .monospacedDigit()
            Text(entry.text)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
