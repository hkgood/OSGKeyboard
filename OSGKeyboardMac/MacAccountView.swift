// MacAccountView.swift
// OSGKeyboard · Mac
//
// `MacAccountSettingsSection` — the account card that opens the Settings
// page: Sign in with Apple, credit balance, and the permanent invitation
// link. Everything here reuses the iOS
// account stack (`AccountSessionCoordinator`, `LiveAccountServices`,
// `ReferralProfileViewModel`) compiled at source level — see project.yml.
//
// Unlike iOS there is no separate Account tab. macOS has one settings surface,
// so the account is simply the first `MacSettingsSection` on it and every row
// sits on the same grid (`settingsCardInset` + `settingsRowMinHeight`) as the
// provider rows below — the old standalone page stacked free-floating VStacks
// that lined up with nothing.
//
// Deliberately no purchase UI. A Developer ID build cannot use StoreKit, so
// credits are bought on iPhone or the web and only *spent* here; the balance
// is server-authoritative either way.

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MacAccountSettingsSection: View {
    @EnvironmentObject private var coordinator: AccountSessionCoordinator
    @Environment(\.themePalette) private var palette

    let language: AppUILanguage

    @State private var isConfirmingDelete = false

    private var lang: AppUILanguage { language }

    var body: some View {
        MacSettingsSection(
            title: MacL10n.string("mac.section.account", language: lang),
            footer: footer
        ) {
            VStack(spacing: MacMetrics.settingsRowGap) {
                switch coordinator.sessionPhase {
                case .restoring:
                    statusRow(MacL10n.string("mac.account.restoring", language: lang))
                case .signedOut:
                    signedOutRow
                case let .signedIn(session):
                    identityRow(session)
                    creditRows
                    MacInviteLinkRow(profile: coordinator.referralProfile, language: lang)
                    referralCountRows
                    accountActionsRow
                    deleteRows
                }
            }
        }
        .task { await coordinator.restoreIfNeeded() }
        .alert(
            MacL10n.string("mac.account.error.title", language: lang),
            isPresented: operationErrorBinding
        ) {
            Button(MacL10n.string("mac.account.error.dismiss", language: lang)) {
                coordinator.dismissOperationError()
            }
        } message: {
            if let key = coordinator.operationErrorKey {
                // The code is appended verbatim: on Mac there is no TestFlight
                // crash trail behind a failed sign-in, and "登录失败，请重试"
                // alone is not something anyone can act on.
                Text(alertMessage(for: key))
            }
        }
    }

    private var footer: String {
        switch coordinator.sessionPhase {
        case .signedOut, .restoring:
            return MacL10n.string("mac.account.signedOut.footnote", language: lang)
        case .signedIn:
            return MacL10n.string("mac.account.credits.purchaseNote", language: lang)
        }
    }

    private func alertMessage(for key: String) -> String {
        let message = MacL10n.string(key, language: lang)
        guard let detail = coordinator.operationErrorDetail else { return message }
        return "\(message)\n(\(detail))"
    }

    // MARK: - Signed out

    /// Title + explanation on the left, the Apple button right-aligned — the
    /// same two-column shape every other settings row uses.
    private var signedOutRow: some View {
        MacInlineRow(
            title: MacL10n.string("mac.account.signedOut.title", language: lang),
            subtitle: MacL10n.string("mac.account.signedOut.body", language: lang)
        ) {
            MacAccountAppleButton(purpose: .signIn, language: lang)
        }
    }

    // MARK: - Signed in

    private func identityRow(_ session: AccountSession) -> some View {
        MacInlineRow(
            title: session.displayName?.isEmpty == false
                ? session.displayName!
                : MacL10n.string("mac.account.profile.unnamed", language: lang),
            subtitle: MacL10n.format(
                "mac.account.profile.accountID",
                language: lang,
                String(session.accountID.uuidString.prefix(8)).lowercased()
            )
        ) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
    }

    @ViewBuilder
    private var creditRows: some View {
        switch coordinator.snapshotPhase {
        case .idle, .loading:
            statusRow(MacL10n.string("mac.account.credits.loading", language: lang))

        case let .loaded(snapshot):
            MacInlineRow(title: MacL10n.string("mac.account.credits.balance", language: lang)) {
                Text("\(snapshot.credits.balance)")
                    .font(TypeStyle.title3)
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
            }
            MacInlineRow(title: MacL10n.string("mac.account.credits.used", language: lang)) {
                Text("\(snapshot.credits.usedCredits)")
                    .font(MacSettingsType.rowLabel)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }

        case let .failed(messageKey):
            MacInlineRow(
                title: MacL10n.string("mac.account.credits.balance", language: lang),
                subtitle: MacL10n.string(messageKey, language: lang)
            ) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var referralCountRows: some View {
        if case let .loaded(snapshot) = coordinator.snapshotPhase {
            let summary = AccountReferralSummary(referrals: snapshot.referrals)
            MacInlineRow(title: MacL10n.string("mac.account.invite.rewarded", language: lang)) {
                Text("\(summary.rewarded)")
                    .font(MacSettingsType.rowLabel)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            MacInlineRow(title: MacL10n.string("mac.account.invite.pending", language: lang)) {
                Text("\(summary.pending)")
                    .font(MacSettingsType.rowLabel)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// Refresh / sign out share one row so the card ends on the row grid rather
    /// than on two stacked full-width buttons.
    private var accountActionsRow: some View {
        HStack(spacing: Spacing.lg) {
            linkButton(
                MacL10n.string("mac.account.credits.refresh", language: lang),
                isBusy: coordinator.isRefreshingAccountData
            ) {
                Task { await coordinator.refreshAccountData(force: true) }
            }
            linkButton(
                MacL10n.string("mac.account.signOut", language: lang),
                isBusy: coordinator.operation == .signingOut
            ) {
                Task { await coordinator.signOut() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacMetrics.settingsCardInset)
        .frame(minHeight: MacMetrics.settingsRowMinHeight)
    }

    @ViewBuilder
    private var deleteRows: some View {
        if isConfirmingDelete {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(MacL10n.string("mac.account.delete.confirmBody", language: lang))
                    .font(MacSettingsType.hint)
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Spacing.lg) {
                    // Apple requires re-authentication before deletion, so this
                    // is a second Sign in with Apple pass, not a confirm button.
                    MacAccountAppleButton(
                        purpose: .deleteAccount,
                        language: lang,
                        onDeleted: { isConfirmingDelete = false }
                    )
                    Button(MacL10n.string("mac.account.delete.cancel", language: lang)) {
                        isConfirmingDelete = false
                    }
                    .buttonStyle(.plain)
                    .font(MacSettingsType.rowLabel)
                    .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, MacMetrics.settingsCardInset)
        } else {
            MacInlineRow(
                title: MacL10n.string("mac.account.delete.title", language: lang),
                subtitle: MacL10n.string("mac.account.delete.body", language: lang)
            ) {
                Button(MacL10n.string("mac.account.delete.action", language: lang)) {
                    isConfirmingDelete = true
                }
                .buttonStyle(.plain)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(palette.danger)
                .accessibilityIdentifier("mac.account.delete.action")
            }
        }
    }

    // MARK: - Helpers

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacMetrics.settingsCardInset)
        .frame(minHeight: MacMetrics.settingsRowMinHeight)
    }

    private func linkButton(
        _ title: String,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            Button(title, action: action)
                .buttonStyle(.plain)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(isBusy ? palette.textTertiary : palette.accent)
                .disabled(isBusy)
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { coordinator.operationErrorKey != nil },
            set: { isPresented in
                if !isPresented { coordinator.dismissOperationError() }
            }
        )
    }
}

// MARK: - Invitation link

/// Separate view so the nested `ReferralProfileViewModel` is observed
/// directly — the parent only observes `AccountSessionCoordinator`, and
/// SwiftUI does not propagate a child ObservableObject's changes through it.
private struct MacInviteLinkRow: View {
    @ObservedObject var profile: ReferralProfileViewModel
    @Environment(\.themePalette) private var palette

    let language: AppUILanguage

    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        content
            .onDisappear { copyResetTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch profile.state {
        case .idle, .loading:
            HStack(spacing: Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(MacL10n.string("mac.account.invite.loading", language: language))
                    .font(MacSettingsType.rowLabel)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacMetrics.settingsCardInset)
            .frame(minHeight: MacMetrics.settingsRowMinHeight)

        case let .loaded(loaded):
            MacInlineRow(
                title: MacL10n.string("mac.account.invite.link", language: language),
                subtitle: loaded.code.inviteURL.absoluteString
            ) {
                Button {
                    copy(loaded.code.inviteURL)
                } label: {
                    Label(
                        MacL10n.string(
                            didCopy
                                ? "mac.account.invite.copied"
                                : "mac.account.invite.copy",
                            language: language
                        ),
                        systemImage: didCopy ? "checkmark" : "doc.on.doc"
                    )
                    .font(MacSettingsType.rowLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .accessibilityIdentifier("mac.account.invite.copy")
            }

        case let .failed(messageKey):
            MacInlineRow(
                title: MacL10n.string("mac.account.invite.link", language: language),
                subtitle: MacL10n.string(messageKey, language: language)
            ) {
                Button(MacL10n.string("mac.account.invite.retry", language: language)) {
                    Task { await profile.refresh() }
                }
                .buttonStyle(.plain)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(palette.accent)
            }
        }
    }

    private func copy(_ url: URL) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        #endif
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
