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
                    list
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
                    Text(Self.dayFormatter.string(from: group.day))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.lg)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .contentMargins(.top, Spacing.md, for: .scrollContent)
        .tabBarScrollBottomPadding()
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

    // MARK: - Mutations

    private func delete(items: [SpeechHistoryEntry], at offsets: IndexSet) {
        for index in offsets {
            store.delete(id: items[index].id)
        }
    }
}
