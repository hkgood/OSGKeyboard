// FlowColdStartOverlay.swift
// OSGKeyboard · Main App
//
// Cold-start handoff hint: a bottom-anchored, full-width gradient that keeps
// the current app visible while Flow proves that voice input is actually
// ready. Failure states reuse the same minimal layout and only change the
// text — permission issues are handled with a single "open Settings" link,
// never a second in-app permission flow.
//
// The overlay ignores the keyboard safe area (full-bleed over Home), so it
// manually tracks keyboard overlap and lifts the gradient + copy together
// to stay glued to the keyboard's top edge. MainTabView also ignores the
// keyboard inset, so system safe-area push cannot be relied on here.

import SwiftUI
import UIKit
import OSGKeyboardShared

struct FlowColdStartContext: Equatable {
    let hostEntry: HostAppEntry?
    var state: FlowColdStartState
    /// Drives preparing / PiP-specific copy (Live Activity vs picture-in-picture).
    var keepAliveMode: FlowKeepAliveMode
}

enum FlowColdStartState: Equatable {
    case preparing
    case ready
    case failed(FlowColdStartFailure)
}

enum FlowColdStartFailure: Equatable {
    case permission(message: String)
    case audio(message: String)
    /// Picture-in-picture keep-alive could not be proven active.
    case pip(message: String)
}

struct FlowColdStartOverlay: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase

    let context: FlowColdStartContext
    let onReturnToHost: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    /// Fraction of the *visible* height (above the keyboard) the gradient occupies.
    private let gradientHeightFraction: CGFloat = 0.50

    /// Distance from the screen bottom to the keyboard's top edge.
    @State private var keyboardOverlap: CGFloat = 0

    /// Ready and failure states dismiss on blank tap; preparing stays
    /// informational only (no accidental dismiss while proving audio).
    private var allowsBlankTapDismiss: Bool {
        switch context.state {
        case .ready, .failed:
            return true
        case .preparing:
            return false
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Keep gradient proportions relative to the canvas above the keyboard
            // so the near-opaque band stays behind the title when the keyboard is up.
            let visibleHeight = max(geo.size.height - keyboardOverlap, 1)
            let gradientHeight = visibleHeight * gradientHeightFraction
            // Above the keyboard the home-indicator inset is already consumed by
            // `keyboardOverlap`; only apply it when the keyboard is hidden.
            let contentBottomPad = keyboardOverlap > 0
                ? Spacing.sm
                : max(geo.safeAreaInsets.bottom, Spacing.sm)

            ZStack(alignment: .bottom) {
                // Full-screen hit sink: must expand explicitly — a bare Color.clear
                // in a bottom-aligned ZStack can collapse and let taps reach Home
                // (e.g. focusing the preview field while this overlay is visible).
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if allowsBlankTapDismiss {
                            onDismiss()
                        }
                    }
                    .allowsHitTesting(true)

                // Full-width bottom gradient: transparent at the top of the
                // band, nearly opaque at the bottom so hint text stays readable.
                LinearGradient(
                    colors: [
                        palette.background.opacity(0.35),
                        palette.background.opacity(0.72),
                        palette.background.opacity(0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: gradientHeight)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                VStack(spacing: Spacing.lg) {
                    content
                        .padding(.horizontal, Spacing.xl)

                    homeIndicator
                        .padding(.bottom, contentBottomPad)
                }
            }
            // Lift gradient + copy as one unit so the opaque band stays glued
            // to the keyboard top edge (or the home indicator when idle).
            .padding(.bottom, keyboardOverlap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
        }
        .onAppear {
            // Cold-start copy asks the user to swipe back — dismiss any in-app
            // keyboard first so Home's preview field cannot steal the scene.
            Self.resignEditingFocus()
            syncKeyboardOverlap(animated: false)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            syncKeyboardOverlap(animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            applyKeyboardOverlap(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { notification in
            // Catches frames missed between mount and the first WillChange
            // (keyboard already visible when the overlay appears).
            applyKeyboardOverlap(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            applyKeyboardOverlap(0, from: notification)
        }
        .animation(.easeInOut(duration: 0.2), value: context.state)
        .accessibilityElement(children: .contain)
    }

    /// Reads the keyboard end frame and animates `keyboardOverlap` with the
    /// system keyboard curve so the gradient rides the same motion.
    private func applyKeyboardOverlap(from notification: Notification) {
        let overlap = Self.keyboardOverlap(from: notification)
        applyKeyboardOverlap(overlap, from: notification)
    }

    private func applyKeyboardOverlap(_ overlap: CGFloat, from notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
            .doubleValue ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardOverlap = overlap
        }
    }

    private func syncKeyboardOverlap(animated: Bool) {
        let overlap = Self.probedKeyboardOverlap()
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardOverlap = overlap
            }
        } else {
            keyboardOverlap = overlap
        }
    }

    /// Screen-bottom → keyboard-top distance in the key window.
    private static func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        guard let window = keyWindow else {
            let bounds = UIScreen.main.bounds
            return max(0, bounds.maxY - frame.minY)
        }
        let frameInWindow = window.convert(frame, from: nil)
        return max(0, window.bounds.maxY - frameInWindow.minY)
    }

    /// Best-effort read when we may have missed keyboard notifications
    /// (overlay mounted while the keyboard was already up).
    private static func probedKeyboardOverlap() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else {
            return 0
        }

        let reference = keyWindow ?? scene.windows.first
        let bounds = reference?.bounds ?? scene.screen.bounds

        // UITextEffectsWindow / UIRemoteKeyboardWindow host the keyboard chrome.
        for window in scene.windows {
            let name = String(describing: type(of: window))
            guard name.contains("Keyboard") || name.contains("TextEffects") else { continue }
            let overlap = max(0, bounds.maxY - window.frame.minY)
            // Full-screen effects windows are not themselves the keyboard —
            // walk for a bottom-docked subview that looks like the input host.
            if overlap >= bounds.height - 1 {
                if let docked = deepestBottomDockedSubview(in: window, referenceBounds: bounds) {
                    return max(0, bounds.maxY - docked.minY)
                }
                continue
            }
            if overlap > 0 {
                return overlap
            }
        }
        return 0
    }

    private static func deepestBottomDockedSubview(
        in window: UIWindow,
        referenceBounds: CGRect
    ) -> CGRect? {
        var best: CGRect?
        func visit(_ view: UIView) {
            let frame = view.convert(view.bounds, to: nil)
            let touchesBottom = abs(frame.maxY - referenceBounds.maxY) < 1.5
            let tallEnough = frame.height > 120
            let notFullScreen = frame.height < referenceBounds.height * 0.92
            if touchesBottom, tallEnough, notFullScreen {
                if best == nil || frame.minY < best!.minY {
                    best = frame
                }
            }
            for child in view.subviews {
                visit(child)
            }
        }
        visit(window)
        return best
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func resignEditingFocus() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: Spacing.md) {
            statusIcon

            Text(title)
                .font(TypeStyle.title3)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)

            actionLink
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch context.state {
        case .preparing:
            ProgressView()
                .tint(palette.accent)
                .scaleEffect(1.1)
                .accessibilityLabel(preparingTitle)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.warning)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var actionLink: some View {
        switch context.state {
        case .preparing, .ready:
            EmptyView()
        case .failed(let failure):
            switch failure {
            case .permission:
                linkButton(AppL10n.string("flow.coldStart.action.settings"), action: onOpenSettings)
            case .audio, .pip:
                linkButton(AppL10n.string("flow.coldStart.action.retry"), action: onRetry)
            }
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TypeStyle.body.weight(.semibold))
                .foregroundStyle(palette.accent)
        }
        .buttonStyle(.plain)
    }

    private var preparingTitle: String {
        switch context.keepAliveMode {
        case .pictureInPicture:
            return AppL10n.string("flow.coldStart.preparing.pip")
        case .liveActivity:
            return AppL10n.string("flow.coldStart.preparing")
        }
    }

    private var title: String {
        switch context.state {
        case .preparing:
            return preparingTitle
        case .ready:
            return AppL10n.string("flow.coldStart.title")
        case .failed(let failure):
            switch failure {
            case .permission:
                return AppL10n.string("flow.coldStart.permission.title")
            case .audio:
                return AppL10n.string("flow.coldStart.audio.title")
            case .pip:
                return AppL10n.string("flow.coldStart.pip.title")
            }
        }
    }

    private var message: String {
        switch context.state {
        case .preparing:
            switch context.keepAliveMode {
            case .pictureInPicture:
                return AppL10n.string("flow.coldStart.preparingHint.pip")
            case .liveActivity:
                return AppL10n.string("flow.coldStart.preparingHint")
            }
        case .ready:
            return AppL10n.string("flow.coldStart.swipeHint")
        case .failed(let failure):
            switch failure {
            case .permission(let message), .audio(let message), .pip(let message):
                return message
            }
        }
    }

    /// System-style home indicator — anchors the swipe-to-return gesture.
    private var homeIndicator: some View {
        Capsule()
            .fill(palette.textTertiary.opacity(context.state == .ready ? 0.55 : 0.35))
            .frame(width: 134, height: 5)
            .accessibilityHidden(true)
    }
}
