// FlowColdStartOverlay.swift
// OSGKeyboard · Main App
//
// Minimal cold-start handoff UI: swipe-back guidance and optional return alert.

import SwiftUI
import OSGKeyboardShared

struct FlowColdStartContext: Equatable {
    let hostEntry: HostAppEntry?
    var showReturnAlert: Bool
}

struct FlowColdStartOverlay: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let context: FlowColdStartContext
    let onReturnToHost: () -> Void
    let onDismiss: () -> Void

    @State private var showAlert: Bool

    init(
        context: FlowColdStartContext,
        onReturnToHost: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.context = context
        self.onReturnToHost = onReturnToHost
        self.onDismiss = onDismiss
        _showAlert = State(initialValue: context.showReturnAlert)
    }

    var body: some View {
        ZStack {
            palette.background.opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Image("OSGBrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)

                Text("flow.coldStart.title")
                    .font(TypeStyle.title3)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(swipeHintKey)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)

                swipeHintAnimation
                    .padding(.top, Spacing.md)

                Button(action: onDismiss) {
                    Text("flow.coldStart.dismiss")
                        .font(TypeStyle.body.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)
            }
            .padding(Spacing.xl)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if context.hostEntry != nil {
                Button(returnButtonTitle, action: onReturnToHost)
            }
            Button("flow.coldStart.dismiss", role: .cancel, action: onDismiss)
        } message: {
            Text("flow.coldStart.alert.message")
        }
    }

    private var swipeHintKey: LocalizedStringKey {
        context.hostEntry == nil
            ? "flow.coldStart.swipeHint"
            : "flow.coldStart.swipeHint.withSystemBack"
    }

    private var alertTitle: String {
        AppL10n.string("flow.coldStart.alert.title")
    }

    private var returnButtonTitle: String {
        guard let entry = context.hostEntry else {
            return AppL10n.string("flow.coldStart.return.generic")
        }
        let appName = AppL10n.string(entry.displayNameKey)
        return AppL10n.format("flow.coldStart.return.named", appName)
    }

    private var swipeHintAnimation: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "chevron.up")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(palette.textTertiary.opacity(0.5))
                .frame(width: 120, height: 5)
        }
        .accessibilityLabel(AppL10n.string("flow.coldStart.swipeAccessibility"))
    }
}
