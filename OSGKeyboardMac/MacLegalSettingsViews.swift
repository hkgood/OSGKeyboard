// MacLegalSettingsViews.swift
// OSGKeyboard · Mac
//
// Privacy policy and third-party license screens (mirrors iOS Settings footer).

import SwiftUI

struct MacPrivacyPolicyView: View {
    let uiLanguage: AppUILanguage
    @Environment(\.themePalette) private var palette

    var body: some View {
        MacLegalWebView(
            resourceName: "PrivacyPolicy",
            scrollToAnchor: privacyScrollAnchor
        )
        .background(palette.background)
        .navigationTitle(MacL10n.string("mac.settings.privacyPolicy", language: uiLanguage))
    }

    private var privacyScrollAnchor: String? {
        switch uiLanguage {
        case .chinese:
            return "zh"
        case .english:
            return "top"
        case .auto:
            return uiLanguage.resolvedLanguageCode().hasPrefix("zh") ? "zh" : "top"
        }
    }
}

struct MacOpenSourceLicensesView: View {
    let uiLanguage: AppUILanguage
    @Environment(\.themePalette) private var palette

    var body: some View {
        List {
            Section {
                Text(MacL10n.string("mac.settings.licenses.footer", language: uiLanguage))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(OpenSourceLicenseCatalog.entries) { entry in
                    NavigationLink {
                        MacOpenSourceLicenseDetailView(entry: entry, uiLanguage: uiLanguage)
                    } label: {
                        HStack {
                            Text(entry.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Spacing.sm)
                            Text(entry.licenseName)
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(MacL10n.string("mac.settings.thirdPartyLicenses", language: uiLanguage))
    }
}

private struct MacOpenSourceLicenseDetailView: View {
    let entry: OpenSourceLicenseCatalog.Entry
    let uiLanguage: AppUILanguage
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let url = entry.url {
                    Link(destination: url) {
                        HStack(spacing: Spacing.xs) {
                            Text(url.absoluteString)
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.accent)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }

                Text(entry.purpose)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.licenseText)
                    .font(TypeStyle.monoSmall)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.lg)
        }
        .background(palette.background)
        .navigationTitle(entry.name)
    }
}
