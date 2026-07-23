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
        // 布局意图：标题 + 统计卡片顶对齐，麦克风栏底对齐，中间的听写预览卡片
        // 吸收全部剩余高度（弹性），因此拉高窗口时是卡片变高而非上下留白。
        //
        // 不用 ScrollView：ScrollView 在测量内容时给子视图的是「理想高度」提案，
        // 会让 `.frame(maxHeight: .infinity)` 的卡片停在最小高度、多余空间变留白。
        // 主窗口最小高度 600，内容恒可容纳，故直接用 GeometryReader 定高铺满
        // （与 iOS 端 HomeView 的弹性预览框同款、已验证可行的模式）。
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // 顶部固定区块：品牌标题 + 统计卡片。
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    heroHeader
                    statCluster
                }
                .padding(.horizontal, MacMetrics.pageHorizontalInset)
                .padding(.top, Spacing.sm)

                // 中间弹性区块：预览卡片撑满标题与麦克风之间的剩余空间。
                dictationStage
                    .padding(.horizontal, MacMetrics.pageHorizontalInset)
                    .padding(.vertical, Spacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 底部固定区块：麦克风按钮 + 两侧信息。
                BottomDictationBar(viewModel: viewModel)
                    .padding(.horizontal, MacMetrics.pageHorizontalInset)
                    .padding(.bottom, Spacing.xs)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
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

    // MARK: - Stats (7-day chart + cumulative grid — shared cluster)

    private var statCluster: some View {
        UsageStatsCluster(
            layout: .split,
            language: lang,
            points: stats.last7Days,
            dictationCharacterCount: stats.dictationCharacterCount,
            dictationDurationSeconds: stats.dictationDurationSeconds,
            translationCharacterCount: stats.translationCharacterCount,
            dictionaryTermCount: viewModel.dictionaryTermCount
        )
    }

    // MARK: - Dictation stage

    private var dictationStage: some View {
        MacCard(padding: Spacing.md, cornerRadius: Radius.large) {
            ZStack(alignment: .topLeading) {
                if viewModel.hasHomePreview {
                    // 总览：累积所有会话文本，内部滚动、自动贴底显示最新一句。
                    ScrollView {
                        Text(viewModel.homePreviewText)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(palette.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: MacMetrics.dictationCanvasMinHeight,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                } else {
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
                }
            }
            // 不再封顶：卡片跟随外层弹性容器把剩余窗口高度全部吃满。
            .frame(minHeight: MacMetrics.dictationCanvasMinHeight, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .animation(Motion.soft, value: viewModel.hasHomePreview)
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
            HStack(spacing: Spacing.sm) {
                Image(systemName: "translate")
                    .foregroundStyle(palette.textSecondary)
                Text(currentTranslationLabel)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .font(MacSettingsType.control)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: MacMetrics.settingsControlHeight)
            .background(
                palette.surfaceElevated,
                in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
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
