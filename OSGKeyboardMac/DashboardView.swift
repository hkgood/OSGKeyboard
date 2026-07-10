// DashboardView.swift
// OSGKeyboard · Mac
//
// Primary workspace: brand voice, asymmetric stats, dictation stage, and
// the record bar. History lives on its own page — no duplicate list here.

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

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heroHeader
                statCluster
                dictationStage
            }
            .padding(.horizontal, MacMetrics.pageHorizontalInset)
            .padding(.top, Spacing.sm)

            // Leftover window height splits evenly above / below the mic bar
            // so spacing stays balanced at any window size.
            Spacer(minLength: Spacing.xs)

            BottomDictationBar(viewModel: viewModel)
                .padding(.horizontal, MacMetrics.pageHorizontalInset)

            Spacer(minLength: Spacing.xs)
        }
        .onAppear { stats.reloadFromDisk() }
        .onReceive(NotificationCenter.default.publisher(for: .usageStatisticsDidSyncFromCloud)) { _ in
            stats.reloadFromDisk()
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(MacL10n.string("mac.brand.tagline", language: lang))
                .font(TypeStyle.pageTitle)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            HStack(spacing: Spacing.sm) {
                Text(MacL10n.string("mac.brand.tagline.subtitle", language: lang))
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textTertiary)

                if let appName = viewModel.foregroundAppName {
                    Text("·")
                        .foregroundStyle(palette.textTertiary.opacity(0.45))
                    Text(MacL10n.format("mac.foregroundApp", language: lang, appName))
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .transition(.opacity)
                        .lineLimit(1)
                }
            }
            .animation(Motion.soft, value: viewModel.foregroundAppName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats (hero word count, full width but content-height —
    // never stretched to match a taller sibling and left with dead air)

    private var statCluster: some View {
        VStack(spacing: Spacing.md) {
            StatCard(
                title: MacL10n.string("mac.stat.words", language: lang),
                value: UsageStatisticsStore.formatCount(
                    stats.dictationCharacterCount,
                    language: lang
                ),
                caption: MacL10n.string("mac.stat.transcribed", language: lang),
                systemImage: "text.alignleft",
                accent: true,
                prominent: true
            )

            HStack(spacing: Spacing.md) {
                StatCard(
                    title: MacL10n.string("mac.stat.dictationTime", language: lang),
                    value: UsageStatisticsStore.formatDuration(
                        stats.dictationDurationSeconds,
                        language: lang
                    ),
                    caption: MacL10n.string("mac.stat.cumulativeDuration", language: lang),
                    systemImage: "waveform"
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
    }

    // MARK: - Dictation stage

    private var dictationStage: some View {
        MacCard(padding: Spacing.md, cornerRadius: Radius.large) {
            ZStack(alignment: .topLeading) {
                if viewModel.transcript.isEmpty {
                    Text(
                        viewModel.isRecording
                            ? MacL10n.string("mac.status.listening", language: lang)
                            : MacL10n.string("mac.status.ready", language: lang)
                    )
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(palette.textTertiary)
                    .contentTransition(.opacity)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: MacMetrics.dictationCanvasMinHeight,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .transition(.opacity)
                } else {
                    Text(viewModel.transcript)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: MacMetrics.dictationCanvasMinHeight,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .transition(.opacity)
                }
            }
            .frame(minHeight: MacMetrics.dictationCanvasMinHeight, maxHeight: 160)
        }
        .animation(Motion.soft, value: viewModel.transcript.isEmpty)
        .animation(Motion.quick, value: viewModel.isRecording)
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
        .padding(.vertical, Spacing.xs)
        // No surface fill — the mic bar sits on the page background so Home
        // stays flat and the canvas above can stay shorter without a second
        // floating card competing for height.
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
            .contentTransition(.opacity)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(palette.surfaceElevated, in: Capsule())
        .animation(Motion.quick, value: viewModel.isProcessing)
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
            .background(palette.surfaceElevated, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // Mic stays geometrically centred: waveform lives inside the button,
    // “press stop” floats above — neither participates in layout.
    private var recordControl: some View {
        recordButton
            .overlay(alignment: .top) {
                if viewModel.isRecording {
                    Text(MacL10n.string("mac.record.pressStop", language: lang))
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize()
                        .offset(y: -22)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .animation(Motion.quick, value: viewModel.isRecording)
    }

    private var recordButton: some View {
        Button(action: viewModel.toggleRecording) {
            ZStack {
                Circle()
                    .fill(viewModel.isRecording ? palette.recordRed : palette.accent)
                    .frame(width: 52, height: 52)
                    .shadow(
                        color: (viewModel.isRecording ? palette.recordRed : palette.accent).opacity(0.35),
                        radius: pulse ? 10 : 5
                    )
                Group {
                    if viewModel.isRecording {
                        MiniWaveform(level: viewModel.audioLevel, barCount: 4, tint: palette.textOnAccent)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(palette.textOnAccent)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
        .opacity(viewModel.isProcessing ? 0.55 : 1)
        .scaleEffect(viewModel.isRecording ? 1.06 : 1)
        .animation(Motion.soft, value: viewModel.isRecording)
        .animation(Motion.quick, value: viewModel.isProcessing)
        .onAppear {
            withAnimation(Motion.breath) {
                pulse = true
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
