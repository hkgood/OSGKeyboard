// FlowColdStartOverlay.swift
// OSGKeyboard · Main App
//
// Minimal cold-start handoff UI: bottom-bar swipe guidance and optional return link.

import SwiftUI
import OSGKeyboardShared

struct FlowColdStartContext: Equatable {
    let hostEntry: HostAppEntry?
}

struct FlowColdStartOverlay: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let context: FlowColdStartContext
    let onReturnToHost: () -> Void
    let onDismiss: () -> Void

    @State private var swipeOffset: CGFloat = 0

    private let homeBarWidth: CGFloat = 134

    var body: some View {
        ZStack {
            palette.background.opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

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

                    Text("flow.coldStart.swipeHint")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)

                    if context.hostEntry != nil {
                        Button(action: onReturnToHost) {
                            Text(returnButtonTitle)
                                .font(TypeStyle.body.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.xl)

                Spacer()

                bottomSwipeGuide
                    .padding(.bottom, Spacing.md)

                Text("flow.coldStart.tapToDismiss")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }

    private var returnButtonTitle: String {
        guard let entry = context.hostEntry else {
            return AppL10n.string("flow.coldStart.return.generic")
        }
        let appName = AppL10n.string(entry.displayNameKey)
        return AppL10n.format("flow.coldStart.return.named", appName)
    }

    private var bottomSwipeGuide: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(palette.textTertiary.opacity(0.35))
                    .frame(width: homeBarWidth, height: 5)

                Circle()
                    .fill(palette.accent)
                    .frame(width: 8, height: 8)
                    .offset(x: swipeOffset)
            }
            .frame(width: homeBarWidth, height: 16)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(palette.textTertiary)
        }
        .accessibilityLabel(AppL10n.string("flow.coldStart.swipeAccessibility"))
        .onAppear {
            swipeOffset = 0
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                swipeOffset = homeBarWidth - 8
            }
        }
    }
}
