// SupportDeveloperSection.swift
// OSGKeyboard · Shared
//
// Optional voluntary tip block for Settings. Does not gate features.

import SwiftUI

/// iOS Settings card for the consumable support tip.
public struct SupportDeveloperSection: View {
    @ObservedObject private var tipManager: TipPurchaseManager
    @Environment(\.themePalette) private var palette

    private let language: AppUILanguage

    @State private var showThankYouAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    public init(
        language: AppUILanguage,
        tipManager: TipPurchaseManager = .shared
    ) {
        self.language = language
        self.tipManager = tipManager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            Text(SharedL10n.string("tip.title", language: language))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                SupportDeveloperTipBody(language: language)

                if tipManager.supportCount > 0 {
                    Text(
                        SharedL10n.format(
                            "tip.thankYou.past",
                            language: language,
                            tipManager.supportCount
                        )
                    )
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.accent)
                }

                tipButton
                    .disabled(isPurchaseInFlight)

                Text(SharedL10n.string("tip.consumableNotice", language: language))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
        .onChange(of: tipManager.purchaseState) { _, newValue in
            switch newValue {
            case .succeeded:
                showThankYouAlert = true
            case .failed(let message):
                errorMessage = message
                showErrorAlert = true
            default:
                break
            }
        }
        .alert(
            SharedL10n.string("tip.thankYou.title", language: language),
            isPresented: $showThankYouAlert
        ) {
            Button(SharedL10n.string("tip.alert.dismiss", language: language)) {
                tipManager.acknowledgePurchaseState()
            }
        } message: {
            Text(SharedL10n.string("tip.thankYou.message", language: language))
        }
        .alert(
            SharedL10n.string("tip.error.title", language: language),
            isPresented: $showErrorAlert
        ) {
            Button(SharedL10n.string("tip.alert.dismiss", language: language)) {
                tipManager.acknowledgePurchaseState()
            }
        } message: {
            Text(errorMessage)
        }
    }

    private var isPurchaseInFlight: Bool {
        switch tipManager.purchaseState {
        case .loading, .purchasing:
            return true
        default:
            return false
        }
    }

    private var tipButton: some View {
        Button {
            Task { await tipManager.purchase() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isPurchaseInFlight {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(tipButtonTitle)
                    .font(TypeStyle.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .foregroundStyle(.white)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tipButtonTitle)
    }

    private var tipButtonTitle: String {
        if let product = tipManager.product {
            return SharedL10n.format("tip.button", language: language, product.displayPrice)
        }
        return SharedL10n.string("tip.buttonFallback", language: language)
    }
}

/// Shared copy + tip button for macOS Settings (Mac chrome wraps this).
public struct SupportDeveloperTipBody: View {
    @Environment(\.themePalette) private var palette

    private let language: AppUILanguage

    public init(language: AppUILanguage) {
        self.language = language
    }

    public var body: some View {
        Text(SharedL10n.string("tip.body", language: language))
            .font(TypeStyle.body)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
