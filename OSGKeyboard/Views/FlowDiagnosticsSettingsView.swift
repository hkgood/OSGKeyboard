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
    @State private var reports: [FlowStartupFailureReport] = []
    @State private var exportURL: URL?
    @State private var corpusExportURL: URL?
    @State private var showsClearConfirmation = false
    @AppStorage(InternalDiagnosticsUploadPreference.storageKey)
    private var uploadsDiagnostics = true
    @State private var pendingUploadCount = 0

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.diagnostics.section")) {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(reportCountText)
                                .font(TypeStyle.bodyEmph)
                                .foregroundStyle(palette.textPrimary)
                            Text(reportStatusText)
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                            if !reports.isEmpty {
                                Text(processBreakdownText)
                                    .font(TypeStyle.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
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
                    internalUploadSection
                    corpusExportSection
                }

                CardSection(title: AppL10n.string("settings.diagnostics.privacy.section")) {
                    Text(privacyBodyText)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.diagnostics.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshReports()
            refreshPendingUploadCount()
        }
        .onChange(of: uploadsDiagnostics) { _, enabled in
            guard enabled else { return }
            // Turning it back on should not wait for the next launch: clear any
            // backoff left by the disabled period and sweep now.
            Task {
                await InternalDiagnosticsUploader.shared.resetDeliveryState()
                await InternalDiagnosticsUploader.shared.uploadPendingReports()
                refreshPendingUploadCount()
            }
        }
        .onChange(of: historyStore.entries) {
            refreshCorpusExport()
        }
        .alert(AppL10n.string("settings.diagnostics.clear.title"), isPresented: $showsClearConfirmation) {
            Button(AppL10n.string("common.cancel"), role: .cancel) {}
            Button(AppL10n.string("settings.diagnostics.clear.confirm"), role: .destructive) {
                FlowFailureLogStore.shared.deleteAllReports()
                refreshReports()
            }
        } message: {
            Text(AppL10n.string("settings.diagnostics.clear.message"))
        }
    }

    /// Beta builds upload; App Store builds never do. Showing the production
    /// wording ("stays on this device") to a tester would be a false promise.
    ///
    /// Hoisted out of the view body on purpose: an inline ternary between two
    /// string literals inside a `Text(...)` argument is enough to push the
    /// SwiftUI type-checker into reporting a bogus error in an unrelated file
    /// in the same compile batch.
    private var privacyBodyText: String {
        let key = AppDistributionChannel.allowsInternalTools
            ? "settings.diagnostics.privacy.body.internal"
            : "settings.diagnostics.privacy.body"
        return AppL10n.string(key, language: config.uiLanguage)
    }

    /// Internal builds only. App Store builds never upload, so this section —
    /// and the preference behind it — simply does not exist for them.
    private var internalUploadSection: some View {
        CardSection(title: AppL10n.string("settings.diagnostics.upload.section")) {
            VStack(spacing: 0) {
                Toggle(isOn: $uploadsDiagnostics) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppL10n.string(
                            "settings.diagnostics.upload.title",
                            language: config.uiLanguage
                        ))
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        Text(AppL10n.string(
                            "settings.diagnostics.upload.description",
                            language: config.uiLanguage
                        ))
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(palette.accent)
                .settingsListRow()
                .accessibilityIdentifier("settings.diagnostics.upload.toggle")

                Divider().background(palette.divider)

                Text(uploadStatusText)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsListRow()
                    .accessibilityIdentifier("settings.diagnostics.upload.status")
            }
            .surfaceCard()
        }
    }

    private var uploadStatusText: String {
        guard uploadsDiagnostics else {
            return AppL10n.string(
                "settings.diagnostics.upload.status.off",
                language: config.uiLanguage
            )
        }
        return String(
            format: AppL10n.string(
                "settings.diagnostics.upload.status.pending",
                language: config.uiLanguage
            ),
            pendingUploadCount
        )
    }

    private func refreshPendingUploadCount() {
        Task {
            let pending = await InternalDiagnosticsUploader.shared.pendingReportCount()
            await MainActor.run { pendingUploadCount = pending }
        }
    }

    private var corpusExportSection: some View {
        CardSection(title: AppL10n.string("settings.diagnostics.corpus.section")) {
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

                Text(AppL10n.string("settings.diagnostics.corpus.privacy"))
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
            from: eligibleCorpus.examples,
            maximumCharacterCount:
                PolishStyleLearningCorpusBuilder
                    .trainingExtractionMaximumCharacterCount
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

    /// Both processes write into the same App Group directory. Splitting the
    /// count is the fastest way to confirm the keyboard side is capturing —
    /// a keyboard-observed timeout used to leave no trace at all.
    private var processBreakdownText: String {
        let hostCount = reports.filter { $0.process == .host }.count
        let keyboardCount = reports.filter { $0.process == .keyboard }.count
        return String(
            format: AppL10n.string(
                "settings.diagnostics.processBreakdown",
                language: config.uiLanguage
            ),
            hostCount,
            keyboardCount
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
        title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            Text(AppL10n.string(title))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right")
                .font(TypeStyle.caption.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .settingsListRow()
        .contentShape(Rectangle())
    }

    private func refreshReports() {
        reportURLs = FlowFailureLogStore.shared.reportURLs()
        reports = FlowFailureLogStore.shared.reports()
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
