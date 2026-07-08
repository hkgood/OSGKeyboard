// MacHistoryView.swift
// OSGKeyboard · Mac
//
// Single-column, day-grouped transcript log rendered as grouped cards (the
// same native `Form` container as Settings). Every entry shows its full text
// inline — no master/detail split, so content never pushes the sidebar out.

import SwiftUI

struct MacHistoryView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @ObservedObject private var historyStore = SpeechHistoryStore.shared
    @Environment(\.themePalette) private var palette

    @State private var showClearConfirmation = false

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

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
        Group {
            if historyStore.entries.isEmpty {
                emptyState
            } else {
                form
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }

    // MARK: - Grouped cards

    private var form: some View {
        Form {
            ForEach(historyStore.groupedByDay, id: \.day) { group in
                Section(Self.dayFormatter.string(from: group.day)) {
                    ForEach(group.items) { entry in
                        row(entry)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .safeAreaInset(edge: .top, spacing: 0) { toolbar }
        .confirmationDialog(
            MacL10n.string("mac.history.clearTitle", language: lang),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(MacL10n.string("mac.history.clearConfirm", language: lang), role: .destructive) {
                historyStore.clearAll()
            }
            Button(MacL10n.string("mac.cancel", language: lang), role: .cancel) {}
        } message: {
            Text(MacL10n.string("mac.history.clearMessage", language: lang))
        }
    }

    private var toolbar: some View {
        HStack {
            Spacer()
            Button {
                showClearConfirmation = true
            } label: {
                Label(MacL10n.string("mac.history.clearConfirm", language: lang), systemImage: "trash")
                    .font(TypeStyle.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .background(palette.background)
    }

    private func row(_ entry: SpeechHistoryEntry) -> some View {
        MacHistoryRow(
            entry: entry,
            time: Self.timeFormatter.string(from: entry.createdAt),
            language: lang,
            copy: { viewModel.copyToClipboard(entry.text) },
            delete: { historyStore.delete(id: entry.id) }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34))
                .foregroundStyle(palette.textTertiary.opacity(0.6))
            Text(MacL10n.string("mac.history.empty", language: lang))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MacHistoryRow: View {
    let entry: SpeechHistoryEntry
    let time: String
    let language: AppUILanguage
    let copy: () -> Void
    let delete: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(time)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
                Text(entry.text)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
