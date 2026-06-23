// OpenSourceLicensesView.swift
// OSGKeyboard · Main App
//
// Standard acknowledgements list: one tappable row per dependency,
// detail screen with the verbatim license text. Reached from
// Settings → About → "Third-Party Licenses".

import SwiftUI
import OSGKeyboardShared

struct OpenSourceLicensesView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
                Text("settings.licenses.footer")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xs)

                VStack(spacing: 0) {
                    ForEach(Array(OpenSourceLicenseCatalog.entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink {
                            OpenSourceLicenseDetailView(entry: entry)
                        } label: {
                            licenseRow(entry)
                        }
                        .buttonStyle(.plain)

                        if index < OpenSourceLicenseCatalog.entries.count - 1 {
                            Divider().background(palette.divider)
                        }
                    }
                }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .stroke(palette.divider, lineWidth: 0.5)
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.licenses.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func licenseRow(_ entry: OpenSourceLicenseCatalog.Entry) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(entry.name)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Spacing.xs)
            Text(entry.licenseName)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail

private struct OpenSourceLicenseDetailView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let entry: OpenSourceLicenseCatalog.Entry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let url = entry.url {
                    Link(destination: url) {
                        HStack(spacing: Spacing.xs) {
                            Text(url.absoluteString)
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.accent)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            MaterialIcon(name: .openInNew, size: 14)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }

                Text(entry.purpose)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.licenseText)
                    .font(TypeStyle.monoSmall)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
