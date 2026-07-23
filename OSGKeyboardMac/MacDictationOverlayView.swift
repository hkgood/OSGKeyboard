// MacDictationOverlayView.swift
// OSGKeyboard · Mac
//
// Compact bottom-of-screen HUD shown while dictating. Lives inside a
// non-activating NSPanel so it never steals focus from the front app.
// One-line layout: status / live transcript preview + waveform + stop.

import SwiftUI

struct MacDictationOverlayView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    /// Called continuously while the user drags the pill (reads the live cursor
    /// position on the controller side). Double-click resets to the default.
    var onDragChanged: (() -> Void)?
    var onDragEnded: (() -> Void)?
    /// Double-click anywhere on the pill to snap it back to the default spot.
    var onResetPosition: (() -> Void)?
    @Environment(\.themePalette) private var palette

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    private var isBusy: Bool {
        viewModel.isRecording || viewModel.isPreparingToRecord || viewModel.isProcessing
    }

    /// Trimmed live / final transcript for the single-line preview.
    private var previewText: String {
        viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPreview: Bool { !previewText.isEmpty }

    private var showsLiveBadge: Bool {
        viewModel.isRecording && viewModel.isStreamingPartial
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            statusDot
            primaryLine
            Spacer(minLength: Spacing.xs)
            trailingControl
        }
        // Fixed content height so the pill never changes height between
        // 识别中 (waveform, 28pt) and 润色中 (small spinner) states.
        .frame(height: 28)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 11)
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 520)
        .fixedSize(horizontal: true, vertical: true)
        .background(palette.surface, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(palette.dividerStrong, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 5)
        // Transparent margin large enough to contain the shadow's reach
        // (radius 14 + y 5). The panel is sized to `fittingSize`, which ignores
        // shadow, so without this room the borderless window clips the shadow
        // into hard translucent-black corners.
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 20, trailing: 16))
        .contentShape(Capsule(style: .continuous))
        // Manual drag: `isMovableByWindowBackground` doesn't work on a
        // non-activating panel, so we move the panel ourselves. The controller
        // reads the live cursor position, so the translation value is unused.
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in onDragChanged?() }
                .onEnded { _ in onDragEnded?() }
        )
        .onTapGesture(count: 2) { onResetPosition?() }
        .help(MacL10n.string("mac.overlay.dragHint", language: lang))
        .animation(Motion.soft, value: hasPreview)
        .animation(Motion.quick, value: viewModel.isRecording)
        .animation(Motion.quick, value: viewModel.isStreamingPartial)
    }

    // MARK: - Primary line (status or one-line transcript)

    @ViewBuilder
    private var primaryLine: some View {
        if hasPreview {
            HStack(spacing: 6) {
                if showsLiveBadge {
                    liveBadge
                }
                Text(previewText)
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: showsLiveBadge ? 280 : 320, alignment: .trailing)
                    .accessibilityLabel(previewText)
            }
        } else {
            HStack(spacing: 6) {
                Text(statusText)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textPrimary)
                    .contentTransition(.opacity)
                if let appName = viewModel.foregroundAppName, isBusy {
                    Text("·")
                        .foregroundStyle(palette.textTertiary.opacity(0.45))
                    Text(appName)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .animation(Motion.quick, value: statusText)
        }
    }

    private var liveBadge: some View {
        Text(MacL10n.string("mac.overlay.live", language: lang))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(palette.recordRed)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(palette.recordRed.opacity(0.12), in: Capsule(style: .continuous))
            .accessibilityHidden(true)
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .animation(Motion.quick, value: viewModel.isRecording)
            .animation(Motion.quick, value: viewModel.isProcessing)
            .animation(Motion.quick, value: viewModel.isPreparingToRecord)
            .animation(Motion.quick, value: viewModel.isStreamingPartial)
    }

    private var dotColor: Color {
        if viewModel.isRecording {
            return viewModel.isStreamingPartial ? palette.accent : palette.recordRed
        }
        if viewModel.isPreparingToRecord || viewModel.isProcessing { return palette.warning }
        return palette.accent
    }

    private var statusText: String {
        if viewModel.isRecording {
            return MacL10n.string("mac.overlay.listening", language: lang)
        }
        if viewModel.isPreparingToRecord {
            return MacL10n.string("mac.overlay.preparing", language: lang)
        }
        if viewModel.isProcessing {
            if viewModel.isStreamingPartial {
                return MacL10n.string("mac.overlay.polishing", language: lang)
            }
            return MacL10n.string("mac.overlay.transcribing", language: lang)
        }
        return MacL10n.string("mac.overlay.done", language: lang)
    }

    // Fixed-size trailing slot so the pill width / height stays steady as the
    // control swaps between waveform, spinner and checkmark.
    private var trailingControl: some View {
        HStack(spacing: Spacing.sm) {
            trailingContent
        }
        .frame(height: 28, alignment: .trailing)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if viewModel.isRecording {
            MiniWaveform(
                level: viewModel.audioLevel,
                barCount: 7,
                tint: (viewModel.isStreamingPartial ? palette.accent : palette.recordRed)
                    .opacity(0.9),
                maxBarHeight: 28,
                barWidth: 3.5,
                barSpacing: 2.5
            )
            stopButton
        } else if viewModel.isPreparingToRecord || viewModel.isProcessing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.accent)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
        }
    }

    private var stopButton: some View {
        Button(action: viewModel.toggleRecording) {
            Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textOnAccent)
                .frame(width: 28, height: 28)
                .background(palette.recordRed, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MacL10n.string("mac.record.stop", language: lang))
    }
}
