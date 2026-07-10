// MacHistoryView.swift
// OSGKeyboard · Mac
//
// Day-grouped transcript log. ScrollView is full-bleed (scrollbar on the
// window edge); title + cards share `pageHorizontalInset` on their content.

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
        VStack(spacing: 0) {
            MacPageHeader(
                title: MacL10n.string("mac.section.history", language: lang),
                subtitle: MacL10n.string("mac.page.history.subtitle", language: lang)
            ) {
                if !historyStore.entries.isEmpty {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Label(
                            MacL10n.string("mac.history.clearConfirm", language: lang),
                            systemImage: "trash"
                        )
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                if historyStore.entries.isEmpty {
                    emptyState
                        .transition(.opacity)
                } else {
                    list
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background)
        .animation(Motion.soft, value: historyStore.entries.isEmpty)
        .confirmationDialog(
            MacL10n.string("mac.history.clearTitle", language: lang),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(MacL10n.string("mac.history.clearConfirm", language: lang), role: .destructive) {
                withAnimation(Motion.soft) { historyStore.clearAll() }
            }
            Button(MacL10n.string("mac.cancel", language: lang), role: .cancel) {}
        } message: {
            Text(MacL10n.string("mac.history.clearMessage", language: lang))
        }
    }

    // MARK: - List

    private var list: some View {
        // Full-bleed ScrollView → scrollbar on the detail pane's right edge.
        // Horizontal inset lives on the content so cards align with the title.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(historyStore.groupedByDay, id: \.day) { group in
                    daySection(group)
                }
            }
            .padding(.horizontal, MacMetrics.pageHorizontalInset)
            .padding(.bottom, Spacing.md)
        }
    }

    private func daySection(_ group: (day: Date, items: [SpeechHistoryEntry])) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Self.dayFormatter.string(from: group.day))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)

            MacCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                        if index < group.items.count - 1 {
                            // Full-bleed like macOS list rows (not iOS inset separators).
                            Divider()
                                .overlay(palette.divider)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: SpeechHistoryEntry) -> some View {
        MacHistoryRow(
            entry: entry,
            time: Self.timeFormatter.string(from: entry.createdAt),
            language: lang,
            copy: { viewModel.copyToClipboard(entry.text) },
            delete: { withAnimation(Motion.soft) { historyStore.delete(id: entry.id) } }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.textTertiary.opacity(0.55))
                .symbolRenderingMode(.hierarchical)
            Text(MacL10n.string("mac.history.empty", language: lang))
                .font(TypeStyle.headline)
                .foregroundStyle(palette.textSecondary)
            Text(MacL10n.string("mac.history.emptyBody", language: lang))
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
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
            .foregroundStyle(isHovering ? palette.danger : palette.textTertiary)
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel(MacL10n.string("mac.delete", language: language))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .animation(Motion.quick, value: isHovering)
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
