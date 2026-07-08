// DashboardView.swift
// OSGKeyboard · Mac
//
// Primary workspace: session stats, dictation canvas, floating record bar.

import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @ObservedObject private var stats: UsageStatisticsStore
    @Environment(\.themePalette) private var palette

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    init(viewModel: MacDictationViewModel) {
        self.viewModel = viewModel
        // Observe through the view model's store instance — a bare
        // `UsageStatisticsStore.shared` on @ObservedObject often misses
        // post-sync @Published updates on macOS.
        self._stats = ObservedObject(wrappedValue: viewModel.usageStatistics)
    }

    // Four equal-width columns — same metrics as the iOS home stats card.
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 120), spacing: Spacing.md),
        count: 4
    )

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let appName = viewModel.foregroundAppName {
                        Text(MacL10n.format("mac.foregroundApp", language: lang, appName))
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    statGrid
                    dictationCanvas
                }
                .padding(Spacing.lg)
            }
            BottomDictationBar(viewModel: viewModel)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
        }
        .onAppear { stats.reloadFromDisk() }
        .onReceive(NotificationCenter.default.publisher(for: .usageStatisticsDidSyncFromCloud)) { _ in
            stats.reloadFromDisk()
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            StatCard(
                title: MacL10n.string("mac.stat.dictationTime", language: lang),
                value: UsageStatisticsStore.formatDuration(
                    stats.dictationDurationSeconds,
                    language: lang
                ),
                caption: MacL10n.string("mac.stat.cumulativeDuration", language: lang),
                systemImage: "waveform",
                accent: true
            )
            StatCard(
                title: MacL10n.string("mac.stat.words", language: lang),
                value: UsageStatisticsStore.formatCount(
                    stats.dictationCharacterCount,
                    language: lang
                ),
                caption: MacL10n.string("mac.stat.transcribed", language: lang),
                systemImage: "text.alignleft"
            )
            StatCard(
                title: MacL10n.string("mac.stat.translation", language: lang),
                value: UsageStatisticsStore.formatCount(
                    stats.translationCharacterCount,
                    language: lang
                ),
                caption: MacL10n.string("mac.stat.cumulativeTranslation", language: lang),
                systemImage: "character.bubble"
            )
            StatCard(
                title: MacL10n.string("mac.stat.dictionary", language: lang),
                value: "\(viewModel.dictionaryTermCount)",
                caption: MacL10n.string("mac.stat.customTerms", language: lang),
                systemImage: "character.book.closed"
            )
        }
    }

    private var dictationCanvas: some View {
        MacCard(padding: Spacing.lg) {
            if viewModel.transcript.isEmpty {
                Text(
                    viewModel.isRecording
                        ? MacL10n.string("mac.status.listening", language: lang)
                        : MacL10n.string("mac.status.ready", language: lang)
                )
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            } else {
                Text(viewModel.transcript)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Floating record bar

struct BottomDictationBar: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette

    @State private var pulse = false

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    var body: some View {
        ZStack {
            HStack {
                translationPicker
                Spacer()
                readinessChip
            }
            recordControl
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .macGlassSurface(in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous), fillOpacity: 0.78)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.dividerStrong, lineWidth: 0.5)
        )
        .shadow(color: palette.textPrimary.opacity(0.12), radius: 18, y: 8)
    }

    private var readinessChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isProcessing ? palette.warning : palette.accent)
                .frame(width: 7, height: 7)
            Text(
                viewModel.isProcessing
                    ? MacL10n.string("mac.status.chipProcessing", language: lang)
                    : MacL10n.string("mac.status.chipReady", language: lang)
            )
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(palette.surfaceElevated, in: Capsule())
    }

    private var translationPicker: some View {
        Menu {
            ForEach(TranslationLanguageCatalog.all) { language in
                Button(translationLabel(for: language)) {
                    viewModel.config.translationTargetLocaleId = language.id
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "translate")
                Text(currentTranslationLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(TypeStyle.caption)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 7)
            .macGlassSurface(in: Capsule(), fillOpacity: 0.66)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var recordControl: some View {
        HStack(spacing: Spacing.sm) {
            if viewModel.isRecording {
                MiniWaveform(level: viewModel.audioLevel)
            }
            Button(action: viewModel.toggleRecording) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? palette.recordRed : palette.accent)
                        .frame(width: 52, height: 52)
                        .macGlassSurface(in: Circle(), fillOpacity: 0.2)
                        .shadow(
                            color: (viewModel.isRecording ? palette.recordRed : palette.accent).opacity(0.5),
                            radius: pulse ? 14 : 6
                        )
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.textOnAccent)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            if viewModel.isRecording {
                Text(MacL10n.string("mac.record.pressStop", language: lang))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var currentTranslationLabel: String {
        let current = TranslationLanguageCatalog.resolve(viewModel.config.translationTargetLocaleId)
        return translationLabel(for: current)
    }

    private func translationLabel(for language: TranslationLanguage) -> String {
        if TranslationLanguageCatalog.isOff(language.id) {
            return MacL10n.string("keyboard.translation.offMenu", language: lang)
        }
        return language.nativeName
    }
}
