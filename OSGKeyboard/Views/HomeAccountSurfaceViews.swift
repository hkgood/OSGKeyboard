// HomeAccountSurfaceViews.swift
// OSGKeyboard · Main App
//
// Views for `HomeAccountSurfacePolicy`: one problem card or one quiet sign-in
// row above the metrics. Navigation stays with `HomeView`.

import OSGKeyboardShared
import SwiftUI

/// Navigation the problem card cannot perform on its own.
struct HomeAccountSurfaceActions {
    var requestPermissions: () -> Void
    var openOwnKeySettings: () -> Void
    var openAccount: () -> Void
    var deferInvitation: () -> Void
}

struct HomeAccountProblemCard: View {
    private enum Tone {
        case good
        case warning
        case danger
    }

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var accountSession: AccountSessionCoordinator
    @ObservedObject private var config = ProviderConfig.shared

    let surface: HomeAccountSurface
    let readiness: HomeServiceReadiness
    /// Short screens (a folded iPhone Duo, iPhone SE) drop footnotes and tighten spacing.
    let compact: Bool
    let actions: HomeAccountSurfaceActions

    @State private var isCodeEntryPresented = false
    @State private var showsManagedCloudConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.sm : Spacing.md) {
            content
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .sheet(isPresented: $isCodeEntryPresented) {
            ReferralCodeEntrySheet()
        }
        .managedCloudConsentAlert(
            isPresented: $showsManagedCloudConsent,
            config: config,
            onAccept: activateCredits
        )
        .accessibilityIdentifier("home.account.problemCard")
    }

    @ViewBuilder
    private var content: some View {
        switch surface {
        case .permissions:
            permissionsContent
        case .invitation(let code):
            invitationContent(code: code)
        case .signInSetup:
            signInSetupContent
        case .chooseService:
            chooseServiceContent
        case .creditsDepleted:
            creditsDepletedContent
        case .creditsUnavailable:
            creditsUnavailableContent
        case .signInPromo, .accountSummary:
            EmptyView()
        }
    }

    // MARK: - States

    private var permissionsContent: some View {
        Group {
            heading(
                statusKey: "home.account.status.setupRequired",
                tone: .warning,
                titleKey: "home.account.permissions.title",
                body: AppPermissions.homePermissionGuidanceMessage
            )
            primaryButton(
                AppPermissions.canRequestPermissionsInApp
                    ? "home.account.permissions.continue"
                    : "home.flow.openSettings",
                action: actions.requestPermissions
            )
            if AppPermissions.canRequestPermissionsInApp {
                footnote("home.account.permissions.footnote")
            }
        }
    }

    private func invitationContent(code: String) -> some View {
        Group {
            heading(
                statusKey: "home.account.status.invitation",
                tone: .good,
                titleKey: "home.account.invitation.title",
                body: AppL10n.string("home.account.invitation.body")
            )
            HStack(spacing: Spacing.sm) {
                Text(AppL10n.format(
                    "home.account.invitation.code",
                    ReferralShortCode.display(code)
                ))
                .font(TypeStyle.bodyEmph.monospaced())
                .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Spacing.xs)
                textLink("home.account.invitation.change") {
                    isCodeEntryPresented = true
                }
            }
            appleSignInButton
            centeredLinks {
                textLink("home.account.invitation.later", muted: true, action: actions.deferInvitation)
            }
        }
    }

    private var signInSetupContent: some View {
        Group {
            heading(
                statusKey: readiness.canDictate
                    ? "home.account.status.dictationReady"
                    : "home.account.status.setupRequired",
                tone: readiness.canDictate ? .good : .warning,
                titleKey: readiness.canDictate
                    ? "home.account.setup.title.polish"
                    : "home.account.setup.title.cloud",
                body: AppL10n.string(
                    readiness.canDictate
                        ? "home.account.setup.body.polish"
                        : "home.account.setup.body.cloud"
                )
            )
            appleSignInButton
            centeredLinks {
                textLink("home.account.ownKey", action: actions.openOwnKeySettings)
                textLink("home.account.haveInvitation") {
                    isCodeEntryPresented = true
                }
            }
            if readiness.canDictate {
                footnote("home.account.setup.footnote")
            }
        }
    }

    private var chooseServiceContent: some View {
        Group {
            heading(
                statusKey: "home.account.status.signedIn",
                tone: .good,
                titleKey: "home.account.choose.title",
                body: chooseServiceBody
            )
            primaryButton(
                "home.account.useCredits",
                isBusy: accountSession.operation == .preparingManagedGateway,
                action: useCredits
            )
            centeredLinks {
                textLink("home.account.ownKey", action: actions.openOwnKeySettings)
            }
        }
    }

    private var creditsDepletedContent: some View {
        Group {
            heading(
                statusKey: "home.account.status.paused",
                tone: .warning,
                titleKey: "home.account.depleted.title",
                body: AppL10n.string("home.account.depleted.body")
            )
            primaryButton("home.account.depleted.add", action: actions.openAccount)
            centeredLinks {
                textLink("home.account.ownKey", action: actions.openOwnKeySettings)
            }
        }
    }

    private var creditsUnavailableContent: some View {
        Group {
            heading(
                statusKey: "home.account.status.connection",
                tone: .danger,
                titleKey: "home.account.unavailable.title",
                body: AppL10n.string("home.account.unavailable.body")
            )
            primaryButton(
                "account.retry",
                isBusy: accountSession.isRefreshingAccountData
            ) {
                Task { await accountSession.refreshAccountData(force: true) }
            }
            centeredLinks {
                textLink("home.account.ownKey", action: actions.openOwnKeySettings)
            }
        }
    }

    private var chooseServiceBody: String {
        guard case let .loaded(snapshot) = accountSession.snapshotPhase else {
            return AppL10n.string("home.account.choose.bodyLoading")
        }
        return AppL10n.format(
            "home.account.choose.body",
            max(snapshot.credits.balance, 0).formatted(.number.grouping(.automatic))
        )
    }

    // MARK: - Credits activation

    private func useCredits() {
        if config.hasAcknowledgedCloudSharing {
            activateCredits()
        } else {
            showsManagedCloudConsent = true
        }
    }

    private func activateCredits() {
        Task {
            await ManagedServiceActivation.activate(
                config: config,
                accountSession: accountSession
            )
        }
    }

    // MARK: - Building blocks

    private func heading(
        statusKey: String,
        tone: Tone,
        titleKey: String,
        body: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(color(for: tone))
                    .frame(width: 6, height: 6)
                Text(AppL10n.string(statusKey))
                    .font(TypeStyle.caption2.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Text(AppL10n.string(titleKey))
                .font(compact ? TypeStyle.headline : TypeStyle.title3)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(body)
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appleSignInButton: some View {
        AccountAppleAuthorizationButton(purpose: .signIn)
            .disabled(accountSession.operation != nil)
    }

    private func primaryButton(
        _ titleKey: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .tint(palette.textOnAccent)
                } else {
                    Text(AppL10n.string(titleKey))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textOnAccent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                palette.accent,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || accountSession.operation != nil)
    }

    private func textLink(
        _ titleKey: String,
        muted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(AppL10n.string(titleKey))
                .font(TypeStyle.footnote.weight(muted ? .medium : .semibold))
                .foregroundStyle(muted ? palette.textTertiary : palette.accent)
                .padding(.vertical, Spacing.xxs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func centeredLinks<Links: View>(@ViewBuilder _ links: () -> Links) -> some View {
        HStack(spacing: Spacing.md) {
            links()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func footnote(_ key: String) -> some View {
        if !compact {
            Text(AppL10n.string(key))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func color(for tone: Tone) -> Color {
        switch tone {
        case .good: return palette.accent
        case .warning: return palette.warning
        case .danger: return palette.danger
        }
    }
}

/// Signed out with a working BYOK setup: the product already works, so the
/// credits offer is a single quiet row rather than a card.
struct HomeSignInPromoRow: View {
    @Environment(\.themePalette) private var palette

    let onOpenAccount: () -> Void

    var body: some View {
        Button(action: onOpenAccount) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(AppL10n.string("home.account.promo.title"))
                        .font(TypeStyle.footnote.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string("home.account.promo.body"))
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(TypeStyle.caption.weight(.semibold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surfaceCard()
        .accessibilityIdentifier("home.account.signInPromo")
    }
}
