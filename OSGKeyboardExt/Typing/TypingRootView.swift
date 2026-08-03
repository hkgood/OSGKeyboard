// TypingRootView.swift
// OSGKeyboard · Keyboard Extension
//
// Typing surface (Phase 1): candidate bar + QWERTY / 123 / symbols.
// Top-leading control returns to the voice surface.

import SwiftUI
import OSGKeyboardShared

enum TypingLayoutMetrics {
    static let outerPaddingTop: CGFloat = 4
    static let outerPaddingBottom: CGFloat = 4
    static let topRegionHeight: CGFloat = KeyboardTopBarMetrics.height
    static let keyRowHeight: CGFloat = 50
    static let keyRowSpacing: CGFloat = 7
    static let keyHorizontalSpacing: CGFloat = 6
    static let bottomRowHeight: CGFloat = KeyboardChromeLayout.actionKeyHeight
    static let verticalKeySpacing: CGFloat = 8
    static let secondRowInset: CGFloat = 18
    static let keyCornerRadius: CGFloat = KeyboardChromeLayout.actionKeyCornerRadius
    /// Extends the bottom corner keys to the same outer edges as Shift / Delete.
    static let bottomLeadingKeyWidth: CGFloat = 70
    static let bottomTrailingKeyWidth: CGFloat = 86
    /// Shared top row + three 50 pt key rows + native spacing + bottom row.
    static let totalHeight: CGFloat = KeyboardChromeLayout.totalHeight
}

struct TypingRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController

    var onInsert: (String) -> Void
    var onDeleteBackward: () -> Void

    static let totalHeight: CGFloat = TypingLayoutMetrics.totalHeight

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        VStack(spacing: 0) {
            topRegion
                .frame(height: TypingLayoutMetrics.topRegionHeight)

            keyGrid
                .padding(.top, TypingLayoutMetrics.verticalKeySpacing)

            bottomRow
                .frame(height: TypingLayoutMetrics.bottomRowHeight)
                .padding(.top, TypingLayoutMetrics.keyRowSpacing)
        }
        .padding(.top, TypingLayoutMetrics.outerPaddingTop)
        .padding(.bottom, TypingLayoutMetrics.outerPaddingBottom)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: Self.totalHeight)
        .background(Color.clear)
        .environment(\.themePalette, palette)
        .onAppear { typing.enterTypingMode() }
    }

    // MARK: - Shared top region

    @ViewBuilder
    private var topRegion: some View {
        if hasCandidateContent {
            candidateBar
        } else {
            idleTopBar
        }
    }

    private var hasCandidateContent: Bool {
        !typing.composition.preedit.isEmpty || !typing.composition.candidates.isEmpty
    }

    private var idleTopBar: some View {
        HStack(spacing: Spacing.xs) {
            KeyboardBrandLogo(action: state.openSettings)

            if let err = typing.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.danger)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            KeyboardTopControls(
                state: state,
                typing: typing,
                palette: palette,
                onInsert: onInsert
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    // MARK: - Candidates

    private var candidateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                if typing.composition.candidates.isEmpty {
                    selectedCandidateLabel(text: typing.composition.preedit)
                } else {
                    ForEach(
                        Array(typing.composition.candidates.enumerated()),
                        id: \.element.id
                    ) { index, candidate in
                        Button {
                            let text = typing.selectCandidate(at: index)
                            if !text.isEmpty { onInsert(text) }
                        } label: {
                            if index == 0 {
                                selectedCandidateLabel(text: candidate.text)
                            } else {
                                Text(candidate.text)
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 40)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
        }
    }

    private func selectedCandidateLabel(text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 19, weight: .medium))
                .lineLimit(1)
            Text(typing.composition.preedit)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .foregroundStyle(keyTextColor)
        .padding(.horizontal, 12)
        .frame(minWidth: 56, minHeight: 40)
        .background(
            selectedCandidateFill,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    // MARK: - Keys

    private var keyGrid: some View {
        VStack(spacing: TypingLayoutMetrics.keyRowSpacing) {
            ForEach(Array(typing.keyRows.enumerated()), id: \.offset) { rowIndex, row in
                GeometryReader { proxy in
                    let inset = rowIndex == 1 ? TypingLayoutMetrics.secondRowInset : 0
                    let weights = row.enumerated().map {
                        keyWeight(label: $0.element, index: $0.offset, rowIndex: rowIndex)
                    }
                    let spacing = TypingLayoutMetrics.keyHorizontalSpacing
                        * CGFloat(max(0, row.count - 1))
                    let availableWidth = proxy.size.width - inset * 2 - spacing
                    let unitWidth = availableWidth / max(1, weights.reduce(0, +))

                    HStack(spacing: TypingLayoutMetrics.keyHorizontalSpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { keyIndex, key in
                            keyButton(key)
                                .frame(width: unitWidth * weights[keyIndex])
                        }
                    }
                    .padding(.horizontal, inset)
                }
                .frame(height: TypingLayoutMetrics.keyRowHeight)
            }
        }
    }

    private func keyButton(_ label: String) -> some View {
        let isSpecial = ["⇧", "⌫", "123", "#+=", "ABC"].contains(label)
        return Button {
            let result = typing.handleKey(label)
            if result == "\u{8}" {
                onDeleteBackward()
            } else if !result.isEmpty {
                onInsert(result)
            }
        } label: {
            keyLabel(label, isSpecial: isSpecial)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(nativeKeyStyle)
    }

    @ViewBuilder
    private func keyLabel(_ label: String, isSpecial: Bool) -> some View {
        switch label {
        case "⇧":
            Image(systemName: typing.shiftActive || typing.capsLock ? "shift.fill" : "shift")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(keyTextColor)
        case "⌫":
            Image(systemName: "delete.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(keyTextColor)
        default:
            Text(label)
                .font(
                    .system(
                        size: isSpecial ? 15 : 22,
                        weight: isSpecial ? .semibold : .regular
                    )
                )
                .foregroundStyle(keyTextColor)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: TypingLayoutMetrics.keyHorizontalSpacing) {
            Button {
                typing.setPage(typing.page == .letters ? .numbers : .letters)
            } label: {
                Text(typing.page == .letters ? "123" : "ABC")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(keyTextColor)
                    .frame(
                        width: TypingLayoutMetrics.bottomLeadingKeyWidth,
                        height: TypingLayoutMetrics.bottomRowHeight
                    )
            }
            .buttonStyle(nativeKeyStyle)

            Button {
                let text = typing.handleSpace()
                if !text.isEmpty { onInsert(text) }
            } label: {
                Text(typing.language == .chinese ? "空格" : "space")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(keyTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: TypingLayoutMetrics.bottomRowHeight)
            }
            .buttonStyle(nativeKeyStyle)

            Button {
                let text = typing.handleReturn()
                if !text.isEmpty { onInsert(text) }
            } label: {
                returnKeyLabel
                    .foregroundStyle(returnKeyTextColor)
                    .frame(
                        width: TypingLayoutMetrics.bottomTrailingKeyWidth,
                        height: TypingLayoutMetrics.bottomRowHeight
                    )
            }
            .buttonStyle(returnKeyStyle)
        }
    }

    @ViewBuilder
    private var returnKeyLabel: some View {
        switch state.returnKeyRole {
        case .newline:
            Image(systemName: "arrow.turn.down.left")
                .font(.system(size: 21, weight: .medium))
        case .send:
            ExtL10n.text(state.returnKeyRole.titleKey)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private func keyWeight(label: String, index: Int, rowIndex: Int) -> CGFloat {
        if label == "⌫" || label == "⇧" || label == "#+=" {
            return 1.35
        }
        if rowIndex == 2 && index == 0 {
            // Double-pinyin semicolon occupies the normal Shift footprint.
            return 1.35
        }
        return 1
    }

    private var keyFill: Color {
        NativeKeyboardKeyColors.fill(for: colorScheme)
    }

    private var keyPressedFill: Color {
        NativeKeyboardKeyColors.pressedFill(for: colorScheme)
    }

    private var keyTextColor: Color {
        NativeKeyboardKeyColors.text(for: colorScheme)
    }

    private var selectedCandidateFill: Color {
        colorScheme == .dark ? Color(white: 0.36) : .white
    }

    private var nativeKeyStyle: NativeKeyboardKeyStyle {
        NativeKeyboardKeyStyle(
            fill: keyFill,
            pressedFill: keyPressedFill,
            border: palette.divider,
            cornerRadius: TypingLayoutMetrics.keyCornerRadius
        )
    }

    private var returnKeyStyle: NativeKeyboardKeyStyle {
        switch state.returnKeyRole {
        case .newline:
            return nativeKeyStyle
        case .send:
            return NativeKeyboardKeyStyle(
                fill: sendKeyFill,
                pressedFill: sendKeyPressedFill,
                border: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08),
                cornerRadius: TypingLayoutMetrics.keyCornerRadius
            )
        }
    }

    private var returnKeyTextColor: Color {
        switch state.returnKeyRole {
        case .newline:
            return keyTextColor
        case .send:
            return .white
        }
    }

    /// The send key stays recognizable in both appearances without becoming neon.
    private var sendKeyFill: Color {
        NativeKeyboardKeyColors.sendFill(for: colorScheme)
    }

    private var sendKeyPressedFill: Color {
        NativeKeyboardKeyColors.sendPressedFill(for: colorScheme)
    }
}
