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
                    FlowLiveActivityBrandMark(size: 28)
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
                FlowLiveActivityBrandMark(size: 22)
            } compactTrailing: {
                FlowLiveActivityTrailingGlyph(phase: context.state.phase)
            } minimal: {
                FlowLiveActivityBrandMark(size: 18)
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
            FlowLiveActivityBrandMark(size: 32)
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
        .padding(.horizontal, 4)
    }
}

/// Branded mark used in compactLeading so users see OSGKeyboard, not the system mic icon.
private struct FlowLiveActivityBrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.55, blue: 1.0),
                            Color(red: 0.22, green: 0.38, blue: 0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "keyboard")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
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
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        case .idle:
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
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
