// MacContentView.swift
// OSGKeyboard · Mac
//
// Compact menu-bar popover for quick dictation.

import SwiftUI

struct MacContentView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            recordButton
            Text(MacL10n.string("mac.hint.holdOption", language: lang))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(viewModel.statusMessage)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)

            if !viewModel.transcript.isEmpty {
                ScrollView {
                    Text(viewModel.transcript)
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(Spacing.xs)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }

            Divider().overlay(palette.divider)
            statusRow
            Divider().overlay(palette.divider)
            footer
        }
        .padding(Spacing.md)
        .background(palette.background)
    }

    private var statusRow: some View {
        HStack(spacing: Spacing.sm) {
            Label(
                viewModel.isCloudMode
                    ? MacL10n.string("mac.mode.cloud", language: lang)
                    : MacL10n.string("mac.mode.local", language: lang),
                systemImage: viewModel.isCloudMode ? "cloud" : "cpu"
            )
            .foregroundStyle(palette.textSecondary)

            Spacer()

            translationMenu

            Spacer()

            Label(MacL10n.string("mac.connected", language: lang), systemImage: "link")
                .foregroundStyle(palette.accent)
        }
        .font(TypeStyle.caption)
        .labelStyle(.titleAndIcon)
    }

    private var translationMenu: some View {
        Menu {
            ForEach(TranslationLanguageCatalog.all) { language in
                Button(MacTranslationDisplay.label(for: language.id, language: lang)) {
                    viewModel.config.translationTargetLocaleId = language.id
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "translate")
                Text(MacTranslationDisplay.label(for: viewModel.config.translationTargetLocaleId, language: lang))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Image("OSGBrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(palette.accent)
            Text("OSGKeyboard")
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if viewModel.isRecording {
                MiniWaveform(level: viewModel.audioLevel, barCount: 4)
            }
        }
    }

    private var recordButton: some View {
        Button(action: viewModel.toggleRecording) {
            HStack {
                Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                Text(
                    viewModel.isRecording
                        ? MacL10n.string("mac.record.stop", language: lang)
                        : MacL10n.string("mac.record.start", language: lang)
                )
                .font(TypeStyle.bodyEmph)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                (viewModel.isRecording ? palette.recordRed : palette.accent),
                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            )
            .foregroundStyle(palette.textOnAccent)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
    }

    private var footer: some View {
        HStack {
            Button(MacL10n.string("mac.openWindow", language: lang)) { MacMainWindow.open() }
                .buttonStyle(.plain)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.accent)
            Spacer()
            Button(MacL10n.string("mac.quit", language: lang)) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }
}
