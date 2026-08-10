// ClipboardKeyboardViews.swift
// OSGKeyboard · Keyboard Extension
//
// Clipboard suggestion strip, enable-guide sheet, and history panel.

import SwiftUI
import OSGKeyboardShared

// MARK: - Suggestion strip (Doubao-style)

struct ClipboardSuggestionBar: View {
    @Environment(\.themePalette) private var palette

    let text: String
    let onInsert: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary)

            Button(action: onInsert) {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            KeyboardCancelButton(
                action: onDismiss,
                accessibilityLabel: ExtL10n.text("keyboard.clipboard.suggestion.dismissA11y"),
                accessibilityHint: ExtL10n.text("keyboard.clipboard.suggestion.dismissHint")
            )
        }
        .frame(height: KeyboardTopBarMetrics.height)
        // No fill — sit in the logo/tab slot over the system keyboard chrome.
        .background(Color.clear)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Shared panel header

/// Title (+ optional accessory) on the leading edge, cancel X on the trailing
/// edge — same 12 pt inset / 44 pt row as the keyboard top bar so the X lands
/// on the clipboard chip's slot when the overlay replaces the surface.
private struct ClipboardPanelHeader<Accessory: View>: View {
    @Environment(\.themePalette) private var palette

    let onClose: () -> Void
    @ViewBuilder let trailingAccessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ExtL10n.text("keyboard.clipboard.panel.title")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)

            trailingAccessory()

            Spacer(minLength: 0)

            // Same chip as edit-mode close — occupies the clipboard button slot.
            KeyboardCancelButton(
                action: onClose,
                accessibilityLabel: ExtL10n.text("keyboard.clipboard.panel.close"),
                accessibilityHint: ExtL10n.text("keyboard.clipboard.panel.closeHint")
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.horizontalInset)
        .frame(height: KeyboardTopBarMetrics.height)
    }
}

// MARK: - Enable guide

struct ClipboardEnableGuideView: View {
    @Environment(\.themePalette) private var palette

    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ClipboardPanelHeader(
                onClose: onClose,
                trailingAccessory: { EmptyView() }
            )

            Spacer(minLength: 0)

            VStack(spacing: 16) {
                ExtL10n.text("keyboard.clipboard.guide.body")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button(action: onOpenSettings) {
                    ExtL10n.text("keyboard.clipboard.guide.cta")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - History panel

struct ClipboardHistoryPanelView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var history: ClipboardHistoryStore

    let onClose: () -> Void
    let onClear: () -> Void
    let onInsert: (String) -> Void
    let onDelete: (UUID) -> Void
    let pastePermissionHint: String?

    var body: some View {
        VStack(spacing: 0) {
            ClipboardPanelHeader(onClose: onClose) {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: KeyboardTopBarMetrics.trailingChipIconSize, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(
                            width: KeyboardTopBarMetrics.trailingChipSize,
                            height: KeyboardTopBarMetrics.trailingChipSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(history.entries.isEmpty)
                .opacity(history.entries.isEmpty ? 0.35 : 1)
            }

            if let pastePermissionHint, !pastePermissionHint.isEmpty {
                Text(pastePermissionHint)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            if history.entries.isEmpty {
                ExtL10n.text("keyboard.clipboard.panel.empty")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(history.entries) { entry in
                            ClipboardHistoryRow(
                                entry: entry,
                                onInsert: { onInsert(entry.text) },
                                onInsertToken: { onInsert($0) },
                                onDelete: { onDelete(entry.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Transparent — let the system keyboard chrome show through.
        .background(Color.clear)
    }
}

private struct ClipboardHistoryRow: View {
    @Environment(\.themePalette) private var palette

    let entry: ClipboardHistoryEntry
    let onInsert: () -> Void
    let onInsertToken: (String) -> Void
    let onDelete: () -> Void

    private var tokens: [String] {
        ClipboardHistoryPolicy.whitespaceTokens(from: entry.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onInsert) {
                    Text(entry.text)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label(
                            ExtL10n.string("keyboard.clipboard.panel.delete"),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }

            if tokens.count >= 2, tokens.count <= 12 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tokens, id: \.self) { token in
                            Button {
                                onInsertToken(token)
                            } label: {
                                Text(token)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        palette.surfaceElevated,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        // Half opacity so the keyboard chrome still reads through the card.
        .background(
            palette.surface.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

// MARK: - Top clipboard button (replaces translation chip slot)

struct KeyboardClipboardMenuButton: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme

    let palette: ThemePalette
    let action: () -> Void

    nonisolated static func == (
        lhs: KeyboardClipboardMenuButton,
        rhs: KeyboardClipboardMenuButton
    ) -> Bool {
        lhs.palette == rhs.palette
    }

    var body: some View {
        Button(action: action) {
            // Neutral chip — mirrors the translation button's off state.
            Image(systemName: "clipboard")
                .font(.system(size: KeyboardTopBarMetrics.trailingChipIconSize, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(
                    width: KeyboardTopBarMetrics.trailingChipSize,
                    height: KeyboardTopBarMetrics.trailingChipSize
                )
                .background(buttonFill, in: Circle())
                .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ExtL10n.text("keyboard.clipboard.a11y"))
        .accessibilityHint(ExtL10n.text("keyboard.clipboard.a11yHint"))
    }

    private var buttonFill: Color {
        colorScheme == .dark ? Color(white: 0.30) : .white
    }
}
