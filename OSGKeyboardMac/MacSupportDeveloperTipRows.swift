// MacSupportDeveloperTipRows.swift
// OSGKeyboard · Mac
//
// Optional consumable tip rows for macOS Settings.

import SwiftUI

struct MacSupportDeveloperTipRows: View {
    @ObservedObject private var tipManager = TipPurchaseManager.shared
    @Environment(\.themePalette) private var palette

    let language: AppUILanguage

    @State private var showThankYouAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetrics.settingsRowGap) {
            SupportDeveloperTipBody(language: language)
                .padding(.horizontal, MacMetrics.settingsCardInset)

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
                .padding(.horizontal, MacMetrics.settingsCardInset)
            }

            MacSettingsToolButton(title: tipButtonTitle, disabled: isPurchaseInFlight) {
                Task { await tipManager.purchase() }
            }
            .padding(.horizontal, MacMetrics.settingsCardInset)
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

    private var tipButtonTitle: String {
        if let product = tipManager.product {
            return SharedL10n.format("tip.button", language: language, product.displayPrice)
        }
        return SharedL10n.string("tip.buttonFallback", language: language)
    }
}
