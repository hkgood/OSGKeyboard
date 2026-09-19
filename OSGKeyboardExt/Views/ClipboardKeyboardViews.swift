// ClipboardKeyboardViews.swift
// OSGKeyboard · Keyboard Extension
//
// Clipboard suggestion strip, enable-guide sheet, and history panel.

import OSGKeyboardShared
import SwiftUI

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
                    .font(TypeStyle.body)
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
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button(action: onOpenSettings) {
                    ExtL10n.text("keyboard.clipboard.guide.cta")
                        .font(TypeStyle.body.weight(.semibold))
                        .foregroundStyle(OSGColor.fixedLightContent)
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

// MARK: - Auto-reply guide

/// One-time nudge layered *over* the live keyboard: a soft scrim keeps the keys
/// faintly visible while a floating pitch + primary action invite the user to
/// turn auto mode on. Tapping the scrim (or the ✕) dismisses it.
struct ClipboardAutoReplyGuideView: View {
    let onClose: () -> Void
    let onTry: () -> Void

    var body: some View {
        ZStack {
            // Dim the keyboard beneath; a tap anywhere off the card dismisses.
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityIdentifier("assistant.autoReply.guide.scrim")
                .accessibilityLabel(ExtL10n.text("keyboard.assistant.autoReply.guide.close"))

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(TypeStyle.title.weight(.semibold))
                    .foregroundStyle(OSGColor.fixedLightContent)

                ExtL10n.text("keyboard.assistant.autoReply.guide.title")
                    .font(TypeStyle.headline)
                    .foregroundStyle(OSGColor.fixedLightContent)
                    .multilineTextAlignment(.center)

                ExtL10n.text("keyboard.assistant.autoReply.guide.body")
                    .font(TypeStyle.footnote)
                    .foregroundStyle(OSGColor.fixedLightContent.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onTry) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(TypeStyle.body.weight(.semibold))
                        ExtL10n.text("keyboard.assistant.autoReply.guidance.cta")
                            .font(TypeStyle.body.weight(.semibold))
                    }
                    .foregroundStyle(OSGColor.fixedLightContent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Palette.light.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityIdentifier("assistant.autoReply.guide.try")
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(TypeStyle.footnote.weight(.semibold))
                            .foregroundStyle(OSGColor.fixedLightContent)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.28), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("assistant.autoReply.guide.close")
                    .accessibilityLabel(ExtL10n.text("keyboard.assistant.autoReply.guide.close"))
                    .accessibilityHint(ExtL10n.text("keyboard.assistant.autoReply.guide.closeHint"))
                }
                .padding(.horizontal, KeyboardTopBarMetrics.horizontalInset)
                .padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("assistant.autoReply.guide")
    }
}

// MARK: - History panel

struct ClipboardHistoryPanelView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var history: ClipboardHistoryStore
    @State private var showClearConfirmation = false

    let onClose: () -> Void
    let onClear: () -> Void
    let onInsert: (String) -> Void
    let onDelete: (UUID) -> Void
    let pastePermissionHint: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ClipboardPanelHeader(onClose: onClose) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(
                                size: KeyboardTopBarMetrics.trailingChipIconSize,
                                weight: .medium
                            ))
                            .foregroundStyle(palette.textSecondary)
                            // HIG minimum hit target; icon stays visually small and centered.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(history.entries.isEmpty)
                    .opacity(history.entries.isEmpty ? 0.35 : 1)
                }

                if let pastePermissionHint, !pastePermissionHint.isEmpty {
                    Text(pastePermissionHint)
                        .font(TypeStyle.caption.weight(.regular))
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
            .allowsHitTesting(!showClearConfirmation)

            if showClearConfirmation {
                clearConfirmationOverlay
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Transparent — let the system keyboard chrome show through.
        .background(Color.clear)
        .animation(.easeOut(duration: 0.16), value: showClearConfirmation)
    }

    private var clearConfirmationOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 38, height: 38)
                .background(palette.surface.opacity(0.35), in: Circle())

            ExtL10n.text("keyboard.clipboard.clear.title")
                .font(TypeStyle.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    showClearConfirmation = false
                } label: {
                    ExtL10n.text("common.cancel")
                        .font(TypeStyle.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .tint(palette.textPrimary)

                Button {
                    // Dismiss the popup before publishing an empty history
                    // so the keyboard never retains stale row content.
                    showClearConfirmation = false
                    onClear()
                } label: {
                    ExtL10n.text("keyboard.clipboard.clear.confirm")
                        .font(TypeStyle.footnote.weight(.semibold))
                        .foregroundStyle(palette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                // Match the system alert's destructive styling used in-app.
                .tint(palette.danger)
            }
        }
        .padding(16)
        .frame(maxWidth: 300)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
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
                        .font(TypeStyle.body)
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
                                    .font(TypeStyle.caption)
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
            in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        )
    }
}

// MARK: - Top clipboard button (right of the translation chip)

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
            // SF Symbol "clipboard" sits optically low; nudge up so it centres
            // in the 34pt chip the same way "xmark" does.
            Image(systemName: "clipboard")
                .font(.system(size: KeyboardTopBarMetrics.trailingChipIconSize, weight: .medium))
                .foregroundStyle(palette.textPrimary.opacity(0.72))
                .offset(y: -0.5)
                .frame(
                    width: KeyboardTopBarMetrics.trailingChipSize,
                    height: KeyboardTopBarMetrics.trailingChipSize
                )
                // Match KeyboardCancelButton: opaque key fill + hairline, no glass.
                .background(NativeKeyboardKeyColors.fill(for: colorScheme), in: Circle())
                .overlay(
                    Circle().stroke(palette.divider, lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant.clipboard")
        .accessibilityLabel(ExtL10n.text("keyboard.clipboard.a11y"))
        .accessibilityHint(ExtL10n.text("keyboard.clipboard.a11yHint"))
    }
}
