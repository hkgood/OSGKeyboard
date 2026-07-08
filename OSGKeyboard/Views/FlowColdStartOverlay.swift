// FlowColdStartOverlay.swift
// OSGKeyboard · Main App
//
// Cold-start handoff hint: a bottom-anchored, full-width gradient that keeps
// the current app visible while Flow proves that voice input is actually
// ready. Failure states reuse the same minimal layout and only change the
// text — permission issues are handled with a single "open Settings" link,
// never a second in-app permission flow.

import SwiftUI
import OSGKeyboardShared

struct FlowColdStartContext: Equatable {
    let hostEntry: HostAppEntry?
    var state: FlowColdStartState
}

enum FlowColdStartState: Equatable {
    case preparing
    case ready
    case failed(FlowColdStartFailure)
}

enum FlowColdStartFailure: Equatable {
    case permission(message: String)
    case audio(message: String)
}

struct FlowColdStartOverlay: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let context: FlowColdStartContext
    let onReturnToHost: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    /// Fraction of the screen height the bottom gradient occupies.
    private let gradientHeightFraction: CGFloat = 0.50

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
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
                .frame(height: geo.size.height * gradientHeightFraction)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                VStack(spacing: Spacing.lg) {
                    content
                        .padding(.horizontal, Spacing.xl)

                    homeIndicator
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, Spacing.sm))
                }
                .allowsHitTesting(false)

                if context.state == .ready {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onDismiss)
                        .ignoresSafeArea()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.2), value: context.state)
        .accessibilityElement(children: .contain)
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
                .accessibilityLabel(AppL10n.string("flow.coldStart.preparing"))
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
            case .audio:
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

    private var title: String {
        switch context.state {
        case .preparing:
            return AppL10n.string("flow.coldStart.preparing")
        case .ready:
            return AppL10n.string("flow.coldStart.title")
        case .failed(let failure):
            switch failure {
            case .permission:
                return AppL10n.string("flow.coldStart.permission.title")
            case .audio:
                return AppL10n.string("flow.coldStart.audio.title")
            }
        }
    }

    private var message: String {
        switch context.state {
        case .preparing:
            return AppL10n.string("flow.coldStart.preparingHint")
        case .ready:
            return AppL10n.string("flow.coldStart.swipeHint")
        case .failed(let failure):
            switch failure {
            case .permission(let message):
                return message
            case .audio(let message):
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
