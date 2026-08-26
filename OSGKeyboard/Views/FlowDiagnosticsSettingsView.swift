// FlowDiagnosticsSettingsView.swift
// OSGKeyboard · Main App
//
// Local-only export and deletion controls for Flow startup failure reports.

import OSGKeyboardShared
import SwiftUI

struct FlowDiagnosticsSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared

    @State private var reportURLs: [URL] = []
    @State private var exportURL: URL?
    @State private var showsClearConfirmation = false

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection("settings.diagnostics.section") {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(reportCountText)
                                .font(TypeStyle.bodyEmph)
                                .foregroundStyle(palette.textPrimary)
                            Text(reportStatusText)
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsListRow()

                        if let exportURL {
                            Divider().background(palette.divider)

                            ShareLink(item: exportURL) {
                                actionRow(
                                    title: "settings.diagnostics.export",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().background(palette.divider)

                            Button(role: .destructive) {
                                showsClearConfirmation = true
                            } label: {
                                actionRow(
                                    title: "settings.diagnostics.clear",
                                    systemImage: "trash"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .surfaceCard()
                }

                CardSection("settings.diagnostics.privacy.section") {
                    Text("settings.diagnostics.privacy.body")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.diagnostics.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshReports)
        .alert("settings.diagnostics.clear.title", isPresented: $showsClearConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("settings.diagnostics.clear.confirm", role: .destructive) {
                FlowFailureLogStore.shared.deleteAllReports()
                refreshReports()
            }
        } message: {
            Text("settings.diagnostics.clear.message")
        }
    }

    private var reportCountText: String {
        String(
            format: AppL10n.string(
                "settings.diagnostics.count",
                language: config.uiLanguage
            ),
            reportURLs.count
        )
    }

    private var reportStatusText: String {
        guard let latest = reportURLs.first,
              let modifiedAt = try? latest.resourceValues(
                forKeys: [.contentModificationDateKey]
              ).contentModificationDate else {
            return AppL10n.string(
                "settings.diagnostics.empty",
                language: config.uiLanguage
            )
        }
        let format = AppL10n.string(
            "settings.diagnostics.latest",
            language: config.uiLanguage
        )
        return String(
            format: format,
            modifiedAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func actionRow(
        title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            Text(title)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .settingsListRow()
        .contentShape(Rectangle())
    }

    private func refreshReports() {
        reportURLs = FlowFailureLogStore.shared.reportURLs()
        exportURL = FlowFailureLogStore.shared.makeExportURL()
    }
}
