// InviteQRFullScreenView.swift
// OSGKeyboard · Main App
//
// Face-to-face mode for the invitation: only the QR code, as large as the
// screen allows, on white at full brightness so a friend's camera locks on
// from arm's length. Tapping anywhere closes it.

import OSGKeyboardShared
import SwiftUI

struct InviteQRFullScreenView: View {
    @Environment(\.dismiss) private var dismiss

    let qrImage: CGImage
    let language: AppUILanguage?

    /// Past this size a phone held at arm's length no longer gains anything.
    private static let maxCodeSide: CGFloat = 440

    var body: some View {
        GeometryReader { proxy in
            let side = min(
                min(proxy.size.width, proxy.size.height) - Spacing.xxl * 2,
                Self.maxCodeSide
            )
            VStack(spacing: Spacing.lg) {
                Image(decorative: qrImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .accessibilityLabel(AppL10n.string("account.referral.poster.accessibility"))

                Text(SharedL10n.string("invite.poster.hint", language: language))
                    .font(TypeStyle.headline)
                    .foregroundStyle(OSGColor.fixedDarkContent.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OSGColor.fixedLightContent.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OSGColor.fixedDarkContent.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(Spacing.md)
            .accessibilityLabel(AppL10n.string("common.done"))
            .accessibilityIdentifier("account.referral.poster.fullScreen.close")
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .boostsScreenBrightness()
        .statusBarHidden()
        .accessibilityAction(.escape) { dismiss() }
        .accessibilityIdentifier("account.referral.poster.fullScreen")
    }
}
