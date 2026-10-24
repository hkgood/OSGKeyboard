// ReferralCodeEntry.swift
// OSGKeyboard · Main App
//
// Manual path for invitations that never opened the app directly. A friend
// who scans a poster usually installs from the App Store, so the Universal
// Link does not fire; instead they type the 8-character code printed on the
// poster and the landing page. Pasting the full link into the field works
// too. The clipboard is never read on its own.

import OSGKeyboardShared
import SwiftUI

/// Green "I have a code" button, styled like the Invite button. The caller
/// owns `isPresented` so it can keep the button on screen while the sheet is
/// open, even if a successful redemption closes the binding window.
struct ReferralCodeEntryButton: View {
    @Binding var isPresented: Bool
    /// Signed-in accounts also get an Invite entry at the bottom of the sheet.
    var invitation: ReferralCode?

    var body: some View {
        Button {
            isPresented = true
        } label: {
            AccountReferralActionLabel(
                titleKey: "account.referral.codeEntry.button",
                systemImage: "gift"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.referral.codeEntry")
        .sheet(isPresented: $isPresented) {
            ReferralCodeEntrySheet(invitation: invitation)
        }
    }
}

/// Text field + confirm. Outcomes are shown inline rather than through the
/// global alert; success closes the sheet after a short confirmation.
struct ReferralCodeEntrySheet: View {
    typealias Outcome = AccountSessionCoordinator.ReferralInputOutcome

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var coordinator: AccountSessionCoordinator

    var invitation: ReferralCode?

    @State private var text = ""
    @State private var isSubmitting = false
    @State private var outcome: Outcome?
    @FocusState private var isFieldFocused: Bool

    /// Long enough to read the confirmation before the sheet closes.
    private static let successDismissDelay: Duration = .milliseconds(1_200)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(AppL10n.string("account.referral.codeEntry.sheetBody"))
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    codeField
                    confirmButton
                    feedback

                    if coordinator.isSignedIn, let invitation {
                        inviteMore(invitation)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(AppL10n.string("account.referral.codeEntry.sheetTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppL10n.string("common.cancel")) { dismiss() }
                        .tint(palette.textPrimary)
                }
            }
            .onAppear { isFieldFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .accessibilityIdentifier("account.referral.codeEntry.sheet")
    }

    private var codeField: some View {
        TextField(AppL10n.string("account.referral.codeEntry.placeholder"), text: $text)
            .font(.system(.title3, design: .monospaced, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .tint(palette.textPrimary)
            .focused($isFieldFocused)
            // Codes are uppercase; links pasted into the field are unaffected.
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
            .onSubmit { Task { await submit() } }
            .onChange(of: text) { _, _ in outcome = nil }
            .settingsListRow()
            .background(
                palette.formSurface,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .accessibilityLabel(AppL10n.string("account.referral.codeEntry.fieldLabel"))
            .accessibilityIdentifier("account.referral.codeEntry.field")
    }

    private var confirmButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(OSGColor.fixedLightContent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            palette.success,
                            in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        )
                } else {
                    AccountReferralActionLabel(
                        titleKey: "account.referral.codeEntry.confirm",
                        systemImage: "checkmark",
                        fillsWidth: true
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .opacity(canSubmit || isSubmitting ? 1 : 0.5)
        .accessibilityIdentifier("account.referral.codeEntry.confirm")
    }

    @ViewBuilder
    private var feedback: some View {
        switch outcome {
        case .invalidInput:
            ReferralFeedbackLabel(messageKey: "account.referral.codeEntry.invalid", isSuccess: false)
        case .failed(let messageKey):
            ReferralFeedbackLabel(messageKey: messageKey, isSuccess: false)
        case .redeemed:
            ReferralFeedbackLabel(messageKey: "account.referral.codeEntry.redeemed", isSuccess: true)
        case .savedForSignIn:
            ReferralFeedbackLabel(messageKey: "account.referral.pendingAfterSignIn", isSuccess: true)
        case nil:
            EmptyView()
        }
    }

    /// The "invite in the sheet" decision: during the binding window the card
    /// shows "I have a code" instead of Invite, so inviting stays one tap away.
    private func inviteMore(_ invitation: ReferralCode) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Divider().background(palette.divider)
            HStack(spacing: Spacing.md) {
                Text(AppL10n.string("account.referral.codeEntry.inviteMore"))
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.xs)
                AccountInvitationButton(
                    invitationURL: invitation.inviteURL,
                    shortCode: invitation.displayShortCode
                )
            }
        }
        .padding(.top, Spacing.sm)
    }

    private var canSubmit: Bool {
        !isSubmitting
            && coordinator.operation == nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        let result = await coordinator.submitReferralInput(text)
        isSubmitting = false
        outcome = result
        guard result == .redeemed || result == .savedForSignIn else { return }
        isFieldFocused = false
        try? await Task.sleep(for: Self.successDismissDelay)
        dismiss()
    }
}

/// "Have an invitation?" row. Signed out it sits under the Apple button on
/// Home and in the account center, and the code is held until sign-in.
struct ReferralCodeEntryRow: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var coordinator: AccountSessionCoordinator

    var invitation: ReferralCode?
    /// Pass a binding when the parent must know the sheet is open.
    var isEntryPresented: Binding<Bool>?

    @State private var isLocallyPresented = false

    private var presentation: Binding<Bool> {
        isEntryPresented ?? $isLocallyPresented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(AppL10n.string("account.referral.codeEntry.title"))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string(
                        coordinator.isSignedIn
                            ? "account.referral.codeEntry.bodySignedIn"
                            : "account.referral.codeEntry.body"
                    ))
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ReferralCodeEntryButton(isPresented: presentation, invitation: invitation)
                    .disabled(coordinator.operation != nil)
            }

            if coordinator.pendingReferralCode != nil, !coordinator.isSignedIn {
                ReferralFeedbackLabel(messageKey: "account.referral.pendingAfterSignIn", isSuccess: true)
            }
        }
    }
}

/// Signed-in variant for the account center: only accounts that have not
/// bound an inviter and are still inside the binding window see it.
struct SignedInReferralCodeCard: View {
    @ObservedObject var profile: ReferralProfileViewModel
    let session: AccountSession

    @State private var isEntryPresented = false

    var body: some View {
        if isEntryPresented || isEligible {
            ReferralCodeEntryRow(invitation: loadedCode, isEntryPresented: $isEntryPresented)
                .padding(Spacing.md)
                .surfaceCard()
                .accessibilityIdentifier("account.referral.codeEntryCard")
        }
    }

    private var loadedCode: ReferralCode? {
        guard case let .loaded(loaded) = profile.state else { return nil }
        return loaded.code
    }

    private var isEligible: Bool {
        guard case let .loaded(loaded) = profile.state else { return false }
        return ReferralBindingWindow.isOpen(for: session, profile: loaded)
    }
}

struct ReferralFeedbackLabel: View {
    @Environment(\.themePalette) private var palette

    let messageKey: String
    let isSuccess: Bool

    var body: some View {
        Label(
            AppL10n.string(messageKey),
            systemImage: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(TypeStyle.footnote)
        .foregroundStyle(isSuccess ? palette.success : palette.danger)
        .fixedSize(horizontal: false, vertical: true)
    }
}
