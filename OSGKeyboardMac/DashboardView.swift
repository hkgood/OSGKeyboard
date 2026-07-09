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
                            .transition(.opacity)
                    }
                    statGrid
                    dictationCanvas
                }
                .animation(Motion.soft, value: viewModel.foregroundAppName)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
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
            ZStack(alignment: .topLeading) {
                if viewModel.transcript.isEmpty {
                    Text(
                        viewModel.isRecording
                            ? MacL10n.string("mac.status.listening", language: lang)
                            : MacL10n.string("mac.status.ready", language: lang)
                    )
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(palette.textTertiary)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .transition(.opacity)
                } else {
                    Text(viewModel.transcript)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                        .transition(.opacity)
                }
            }
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
        .padding(.vertical, Spacing.sm)
        .macGlassSurface(in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous), fillOpacity: 1)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.dividerStrong, lineWidth: 0.5)
        )
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
            .macGlassSurface(in: Capsule(), fillOpacity: 0.66)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // 麦克风按钮始终居中固定：录音时的波形放进按钮内部，
    // “按停止”提示作为浮层显示在按钮上方，二者均不参与布局，
    // 因此按下 Option 触发录音时按钮位置不会发生偏移。
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
                        // 与 iOS 一致：录音时在红色按钮内部显示实时波形
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
