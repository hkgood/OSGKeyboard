// LastInputEditView.swift
// OSGKeyboard · Keyboard Extension

import SwiftUI
import OSGKeyboardShared

struct LastInputEditView: View {
    private enum Layout {
        static let primaryButtonHeight: CGFloat = 50
        static let primaryButtonWidth: CGFloat = primaryButtonHeight * 3
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: KeyboardState
    @State private var selectedPage: Int? = 0

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar.frame(height: KeyboardTopBarMetrics.height)
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    pages
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 0) {
                        statusLine.frame(height: 18)
                        pageIndicator.frame(height: 12)
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 174)
                .contentShape(Rectangle())
                .simultaneousGesture(reviewSwipeGesture)
                primaryRow.frame(height: 55)
            }
            .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardChromeLayout.totalHeight)
        .environment(\.themePalette, palette)
        .onChange(of: state.editSession) { _, newValue in
            guard let review = newValue.review else {
                selectedPage = 0
                return
            }
            // Set page before the pager remounts (see `.id` on `pages`) so the
            // fresh ScrollView opens on「编辑后」instead of flipping the dots
            // while still showing「原文」.
            selectedPage = 1
            if !reduceMotion {
                // Re-assert after layout; spring is only for subsequent swipes.
                Task { @MainActor in
                    await Task.yield()
                    guard state.editSession.review?.utteranceID == review.utteranceID else { return }
                    selectedPage = 1
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            KeyboardBrandLogo(action: state.openSettings)
            Spacer(minLength: 0)
            KeyboardCancelButton(
                action: state.closeEditMode,
                accessibilityLabel: ExtL10n.text("keyboard.edit.close"),
                accessibilityHint: ExtL10n.text("keyboard.edit.closeHint")
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    @ViewBuilder
    private var pages: some View {
        if let source = state.editSession.source {
            EditTextPager(
                originalTitle: ExtL10n.string("keyboard.edit.page.original"),
                originalText: source.reference.displayText,
                editedTitle: ExtL10n.string("keyboard.edit.page.edited"),
                editedText: state.editSession.review?.resultText,
                contentBottomInset: 30,
                selectedPage: $selectedPage
            )
            // Remount when review text arrives so scrollPosition can open on page 1.
            .id(state.editSession.review?.utteranceID.uuidString ?? "edit-source")
        }
    }

    private var statusLine: some View {
        Text(editTranscript)
            .font(TypeStyle.caption)
            .foregroundStyle(isFailure ? palette.warning : palette.textPrimary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity)
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(selectedPage != 1 ? palette.textPrimary : palette.textTertiary.opacity(0.45))
                .frame(width: 5, height: 5)
            Circle()
                .fill(selectedPage == 1 ? palette.textPrimary : palette.textTertiary.opacity(0.45))
                .frame(width: 5, height: 5)
        }
        .opacity(state.editSession.review == nil ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var primaryRow: some View {
        HStack(spacing: Spacing.sm) {
            helperText(leftHelper)
            Button(action: primaryAction) {
                ZStack {
                    Color.clear
                    if case .listening = state.editSession {
                        Capsule()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                            .scaleEffect(1 + min(max(state.level, 0), 1) * 0.08)
                            .animation(Motion.soft, value: state.level)
                    }
                    primaryIcon
                }
                .frame(
                    width: Layout.primaryButtonWidth,
                    height: Layout.primaryButtonHeight
                )
                // 实心填充、无外扩阴影：避免玻璃投影被键盘底边裁切。
                .background(palette.accent, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)
            .accessibilityLabel(Text(primaryAccessibilityLabel))
            helperText(rightHelper)
        }
    }

    private func helperText(_ value: String) -> some View {
        Text(value)
            .font(TypeStyle.caption)
            .foregroundStyle(palette.textSecondary.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(reviewSwipeGesture)
    }

    @ViewBuilder
    private var primaryIcon: some View {
        switch state.editSession {
        case .preparing, .processing, .applying, .appending:
            ProgressView().tint(.white)
        case .review:
            Image(systemName: "checkmark")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
        case .listening:
            WaveformView(
                level: state.level,
                barCount: 7,
                color: .white,
                active: true
            )
            .frame(width: 35, height: 22)
            .clipped()
        default:
            Image(systemName: "mic.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var primaryDisabled: Bool {
        switch state.editSession {
        case .preparing, .processing, .applying, .appending:
            return true
        default:
            return false
        }
    }

    private func primaryAction() {
        switch state.editSession {
        case .listening:
            state.stopEditListening()
        case .review:
            state.confirmEditResult()
        case .failed:
            state.beginEditLastInput()
        default:
            break
        }
    }

    private var editTranscript: String {
        if case .failed(_, let message) = state.editSession {
            return message
        }
        return state.lastTranscript
    }

    private var isFailure: Bool {
        if case .failed = state.editSession { return true }
        return false
    }

    private var leftHelper: String {
        state.editSession.review == nil
            ? ExtL10n.string("keyboard.edit.helper.speak")
            : ExtL10n.string("keyboard.edit.helper.compare")
    }

    private var rightHelper: String {
        if state.editSession.review != nil {
            return state.editCanReplaceOriginal
                ? ExtL10n.string("keyboard.edit.helper.apply")
                : ExtL10n.string("keyboard.edit.helper.append")
        }
        return ExtL10n.string("keyboard.edit.helper.finish")
    }

    private var primaryAccessibilityLabel: String {
        if state.editSession.review != nil {
            return state.editCanReplaceOriginal
                ? ExtL10n.string("keyboard.edit.apply")
                : ExtL10n.string("keyboard.edit.append")
        }
        return ExtL10n.string("keyboard.edit.stop")
    }

    private var reviewSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard state.editSession.review != nil else { return }
                let translation = value.predictedEndTranslation
                guard abs(translation.width) > abs(translation.height) * 1.2,
                      abs(translation.width) >= 28 else {
                    return
                }
                let targetPage = translation.width < 0 ? 1 : 0
                guard selectedPage != targetPage else { return }
                if reduceMotion {
                    selectedPage = targetPage
                } else {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                        selectedPage = targetPage
                    }
                }
            }
    }
}
