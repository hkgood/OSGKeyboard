// FlowDiagnosticsSettingsView.swift
// OSGKeyboard · Main App
//
// Local-only export and deletion controls for Flow startup failure reports.

import OSGKeyboardShared
import SwiftUI

struct FlowDiagnosticsSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var historyStore = SpeechHistoryStore.shared

    @State private var reportURLs: [URL] = []
    @State private var exportURL: URL?
    @State private var corpusExportURL: URL?
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

                if AppDistributionChannel.allowsInternalTools {
                    corpusExportSection
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
        .onChange(of: historyStore.entries) {
            refreshCorpusExport()
        }
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

    private var corpusExportSection: some View {
        CardSection("settings.diagnostics.corpus.section") {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(corpusCountText)
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(corpusStatusText)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsListRow()

                if let corpusExportURL {
                    Divider().background(palette.divider)

                    ShareLink(item: corpusExportURL) {
                        actionRow(
                            title: "settings.diagnostics.corpus.export",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.diagnostics.corpus.export")
                }

                Divider().background(palette.divider)

                Text("settings.diagnostics.corpus.privacy")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsListRow()
            }
            .surfaceCard()
        }
    }

    private var corpus: PolishStyleLearningCorpus {
        let eligibleCorpus = PolishStyleLearningCorpusBuilder.build(
            from: historyStore.snapshot()
        )
        return PolishStyleLearningCorpusBuilder.trainingWindow(
            from: eligibleCorpus.examples
        )
    }

    private var corpusCountText: String {
        String(
            format: AppL10n.string(
                "settings.diagnostics.corpus.count",
                language: config.uiLanguage
            ),
            corpus.examples.count,
            corpus.effectiveCharacterCount
        )
    }

    private var corpusStatusText: String {
        let key = corpus.examples.isEmpty
            ? "settings.diagnostics.corpus.empty"
            : "settings.diagnostics.corpus.ready"
        return AppL10n.string(key, language: config.uiLanguage)
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
        refreshCorpusExport()
    }

    private func refreshCorpusExport() {
        guard AppDistributionChannel.allowsInternalTools else {
            corpusExportURL = nil
            return
        }
        corpusExportURL = PolishStyleCorpusExportStore.shared.makeExportURL(
            from: historyStore.snapshot()
        )
    }
}
