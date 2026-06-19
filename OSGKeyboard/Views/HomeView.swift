// HomeView.swift
// OSGKeyboard · Main App
//
// Minimal home: logo, status capsule, flow hints, inline preview field.

import SwiftUI
import OSGKeyboardShared

struct HomeView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @FocusState private var previewFocused: Bool
    @State private var previewText = ""

    private var sessionIsLive: Bool {
        flowManager.isActive || flowManager.isStarting
    }

    var body: some View {
        GeometryReader { geo in
            let gradientHeight = geo.size.height * 0.30 + geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                sessionHeaderGradient(height: gradientHeight)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    logoHeader
                        .padding(.top, Spacing.xxxl)
                        .padding(.bottom, Spacing.xl)

                    flowSessionExtras
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.lg)

                    previewField
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    engineStatusLine
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(palette.background)
        }
    }

    // MARK: - Top gradient

    private func sessionHeaderGradient(height: CGFloat) -> some View {
        LinearGradient(
            colors: sessionIsLive
                ? [
                    palette.accent.opacity(0.28),
                    palette.accent.opacity(0.10),
                    palette.background.opacity(0)
                ]
                : [
                    palette.textTertiary.opacity(0.14),
                    palette.textTertiary.opacity(0.05),
                    palette.background.opacity(0)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(Motion.soft, value: sessionIsLive)
    }

    // MARK: - Header

    private var logoHeader: some View {
        VStack(spacing: Spacing.xxl) {
            Image("osglogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 34)
                .accessibilityHidden(true)

            statusCapsule
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    private var statusCapsule: some View {
        HStack(spacing: Spacing.sm) {
            Text(statusLine)
                .font(TypeStyle.status)
                .foregroundStyle(palette.textSecondary)
                .fixedSize()

            capsuleDivider

            flowCapsuleSegment

            if flowManager.isActive {
                Button {
                    flowManager.endSession()
                } label: {
                    Text("home.flow.endShort")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textOnAccent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(capsuleBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(palette.divider, lineWidth: 0.5)
        )
        .animation(Motion.soft, value: flowManager.isActive)
    }

    private var capsuleDivider: some View {
        Circle()
            .fill(palette.dividerStrong)
            .frame(width: 3, height: 3)
    }

    @ViewBuilder
    private var flowCapsuleSegment: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(flowStatusColor)
                .frame(width: 6, height: 6)

            if flowManager.isActive, let expires = flowManager.sessionExpiresAt {
                Text("home.flow.label")
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textPrimary)
                Text(":")
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textTertiary)
                Text(expires, style: .timer)
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            } else {
                Text(flowStatusTitle)
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var capsuleBackground: Color {
        sessionIsLive
            ? palette.accentMuted.opacity(0.55)
            : palette.surface.opacity(0.88)
    }

    private var statusLine: String {
        config.isConfigured
            ? NSLocalizedString("home.status.ready", comment: "")
            : NSLocalizedString("home.status.setupIncomplete", comment: "")
    }

    // MARK: - Flow extras (warnings / hint)

    @ViewBuilder
    private var flowSessionExtras: some View {
        if let warning = flowManager.sessionWarning {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(warning)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                if !AppPermissions.flowRequirementsMet {
                    Button {
                        AppPermissions.openSystemSettings()
                    } label: {
                        Text("home.flow.openSettings")
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        } else if !flowManager.isActive {
            Text("home.flow.hint")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.sm)
        }
    }

    private var flowStatusColor: Color {
        if flowManager.isActive { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if flowManager.sessionWarning != nil { return palette.warning }
        return palette.textTertiary
    }

    private var flowStatusTitle: LocalizedStringKey {
        if flowManager.isActive { return "home.flow.active" }
        if flowManager.isStarting { return "home.flow.starting" }
        return "home.flow.inactive"
    }

    // MARK: - Preview field

    private var previewField: some View {
        TextField("home.preview.placeholder", text: $previewText, axis: .vertical)
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.accent)
            .focused($previewFocused)
            .lineLimit(1...100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
            .background(palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(previewFocused ? palette.dividerStrong : palette.divider, lineWidth: 0.5)
            )
    }

    private var engineStatusLine: some View {
        Text(
            EngineServiceLabel.summary(
                engineMode: config.engineMode,
                providerId: config.providerId,
                model: config.model
            )
        )
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
