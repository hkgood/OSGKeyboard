// AccountRewardsCard.swift
// OSGKeyboard · Main App
//
// Compact Home account surface. Signed-in users see the same credit progress
// and invitation controls formerly shown in Settings; signed-out users see
// the concrete free-credit paths before authenticating.

import OSGKeyboardShared
import SwiftUI

struct AccountRewardsCard: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var coordinator: AccountSessionCoordinator
    @ObservedObject private var config = ProviderConfig.shared

    let onOpenAccount: () -> Void

    var body: some View {
        Group {
            switch coordinator.sessionPhase {
            case .restoring:
                loadingContent("account.settings.restoring")
            case .signedOut:
                signedOutContent
            case .signedIn:
                signedInContent
            }
        }
        .surfaceCard()
        .task(id: coordinator.accountID) {
            guard coordinator.isSignedIn else { return }
            await coordinator.refreshAccountData()
        }
        .alert("account.error.title", isPresented: operationErrorBinding) {
            Button("common.done") {
                coordinator.dismissOperationError()
            }
        } message: {
            if let key = coordinator.operationErrorKey {
                Text(LocalizedStringKey(key))
            }
        }
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: "gift")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 38, height: 38)
                    .background(
                        palette.textPrimary.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: Radius.medium,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("home.accountRewards.signedOut.title")
                        .font(TypeStyle.headline)
                        .foregroundStyle(palette.textPrimary)
                    Text("home.accountRewards.signedOut.summary")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AccountAppleAuthorizationButton(purpose: .signIn)
                .disabled(coordinator.operation != nil)
        }
        .padding(Spacing.md)
    }

    private var signedInContent: some View {
        VStack(spacing: 0) {
            switch coordinator.snapshotPhase {
            case let .loaded(snapshot):
                creditSummary(snapshot)
            case .failed:
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("account.error.load")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("account.retry") {
                        Task { await coordinator.refreshAccountData(force: true) }
                    }
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.accent)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .idle, .loading:
                loadingContent("account.loading.center")
            }

            Divider().background(palette.divider)
            AccountReferralLinkView(viewModel: coordinator.referralProfile)
        }
    }

    private func creditSummary(_ snapshot: AccountCenterSnapshot) -> some View {
        let totalCredits = creditTotal(snapshot)
        return Button(action: onOpenAccount) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(creditRemainingText(snapshot.credits.balance))
                            .font(TypeStyle.title3.monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text("account.credits.balance")
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer(minLength: Spacing.xs)

                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text(creditUsedText(snapshot.credits.usedCredits))
                        Text(creditTotalText(totalCredits))
                    }
                    .font(TypeStyle.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .frame(minWidth: 32, minHeight: 32)
                        .accessibilityHidden(true)
                }

                AccountCreditProgress(
                    remaining: snapshot.credits.balance,
                    used: snapshot.credits.usedCredits,
                    showsLabels: false
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(Spacing.md)
    }

    private func loadingContent(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .tint(palette.accent)
            Text(key)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .settingsListRow()
    }

    private func creditTotal(_ snapshot: AccountCenterSnapshot) -> Int64 {
        let remaining = max(snapshot.credits.balance, 0)
        let used = max(snapshot.credits.usedCredits, 0)
        let (total, overflow) = remaining.addingReportingOverflow(used)
        return overflow ? Int64.max : total
    }

    private func creditRemainingText(_ remaining: Int64) -> String {
        AppL10n.format(
            "account.credits.remainingCompact",
            language: config.uiLanguage,
            max(remaining, 0).formatted(.number.grouping(.automatic))
        )
    }

    private func creditUsedText(_ used: Int64) -> String {
        AppL10n.format(
            "account.credits.usedCompact",
            language: config.uiLanguage,
            max(used, 0).formatted(.number.grouping(.automatic))
        )
    }

    private func creditTotalText(_ total: Int64) -> String {
        AppL10n.format(
            "account.credits.totalValueCompact",
            language: config.uiLanguage,
            total.formatted(.number.grouping(.automatic))
        )
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { coordinator.operationErrorKey != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismissOperationError()
                }
            }
        )
    }
}

private struct AccountReferralLinkView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var viewModel: ReferralProfileViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                retryRow(
                    messageKey: "account.referral.loadLink",
                    actionKey: "account.referral.loadLink"
                )
            case .loading:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)
                    Text("account.referral.loadingLink")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            case .failed(let messageKey):
                retryRow(messageKey: messageKey, actionKey: "account.retry")
            case .loaded(let profile):
                loadedContent(profile)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("account.referral.profile")
    }

    private func loadedContent(_ profile: ReferralProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text("account.referral.equalRewardDescription")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.xs)
                AccountInvitationButton(invitationURL: profile.code.inviteURL)
            }

            if viewModel.isRefreshing {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("account.referral.refreshingLink")
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
            } else if let refreshErrorKey = viewModel.refreshErrorKey {
                retryRow(messageKey: refreshErrorKey, actionKey: "account.retry")
            }
        }
    }

    private func retryRow(
        messageKey: String,
        actionKey: LocalizedStringKey
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(LocalizedStringKey(messageKey))
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Spacing.xs)
            Button(actionKey) {
                Task { await viewModel.refresh() }
            }
            .font(TypeStyle.bodyEmph)
            .foregroundStyle(palette.accent)
        }
    }
}
