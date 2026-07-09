// FlowLiveActivityWidget.swift
// OSGKeyboard · Live Activity
//
// Dynamic Island compact leading shows the OSGKeyboard mark instead of the
// generic system microphone glyph that appears without a Live Activity.

import ActivityKit
import SwiftUI
import WidgetKit

struct FlowLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlowActivityAttributes.self) { context in
            FlowLiveActivityLockScreenView(phase: context.state.phase)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FlowLiveActivityBrandMark(height: 16)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FlowLiveActivityPhaseLabel(phase: context.state.phase)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("OSGKeyboard")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FlowLiveActivityPhaseCaption(phase: context.state.phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                FlowLiveActivityBrandMark(height: 12)
            } compactTrailing: {
                FlowLiveActivityTrailingGlyph(phase: context.state.phase)
            } minimal: {
                // The minimal slot is a tiny circle; a short wordmark keeps
                // the natural ratio without overflowing its bounds.
                FlowLiveActivityBrandMark(height: 6)
            }
            .keylineTint(Color(red: 0.35, green: 0.55, blue: 1.0))
        }
    }
}

// MARK: - Views

private struct FlowLiveActivityLockScreenView: View {
    let phase: FlowActivityAttributes.ContentState.Phase

    var body: some View {
        HStack(spacing: 12) {
            FlowLiveActivityBrandMark(height: 13)
            VStack(alignment: .leading, spacing: 4) {
                Text("OSGKeyboard")
                    .font(.headline)
                FlowLiveActivityPhaseCaption(phase: phase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FlowLiveActivityTrailingGlyph(phase: phase)
        }
        // iOS Live Activity lock-screen content needs margins so the leading
        // logo and trailing glyph don't touch the card edges.
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Branded mark used in compactLeading so users see OSGKeyboard, not the system mic icon.
/// Transparent white OSG glyphs render directly on the black Dynamic Island.
private struct FlowLiveActivityBrandMark: View {
    /// The OSG wordmark is wide and short; pin the width to its true aspect
    /// ratio so it never collapses into a thin sliver inside a square frame.
    private static let aspectRatio: CGFloat = 912.0 / 251.0

    /// Rendered glyph height; width follows the wordmark's natural ratio.
    let height: CGFloat

    var body: some View {
        Image("OSGLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: height * Self.aspectRatio, height: height)
            .accessibilityLabel("OSGKeyboard")
    }
}

private struct FlowLiveActivityTrailingGlyph: View {
    let phase: FlowActivityAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .recording:
            Image(systemName: "waveform")
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .processing:
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .idle:
            // Session ready but NOT listening — avoid a mic glyph so users
            // don't think the keyboard is recording in the background.
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct FlowLiveActivityPhaseLabel: View {
    let phase: FlowActivityAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .recording:
            Text("REC")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.red)
        case .processing:
            Text("…")
                .font(.title3.weight(.semibold))
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct FlowLiveActivityPhaseCaption: View {
    let phase: FlowActivityAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .idle:
            Text("Voice session active")
        case .recording:
            Text("Listening…")
        case .processing:
            Text("Transcribing…")
        }
    }
}
