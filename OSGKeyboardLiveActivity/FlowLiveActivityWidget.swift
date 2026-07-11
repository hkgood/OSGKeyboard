// FlowLiveActivityWidget.swift
// OSGKeyboard · Live Activity
//
// Dynamic Island compact leading shows the OSGKeyboard mark instead of the
// generic system microphone glyph that appears without a Live Activity.

import ActivityKit
import SwiftUI
import WidgetKit

struct FlowLiveActivityWidget: Widget {
    /// Deep link that restarts the Flow session. When the host process is
    /// dead the activity goes stale; tapping it must take the *cold-start*
    /// path (same as the keyboard's mic button), not just open the app.
    private static let reconnectURL = URL(string: "osgkeyboard://startflow")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlowActivityAttributes.self) { context in
            FlowLiveActivityLockScreenView(
                phase: context.state.phase,
                isStale: context.isStale
            )
            .activityBackgroundTint(Color.black.opacity(0.82))
            .activitySystemActionForegroundColor(.white)
            // Deep-link to a session restart only when the host is dead —
            // tapping a HEALTHY activity should just open the app, not
            // force a cold-start handoff into a running session.
            .widgetURL(context.isStale ? Self.reconnectURL : nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FlowLiveActivityBrandMark(height: 16)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FlowLiveActivityPhaseLabel(phase: context.state.phase, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("OSGKeyboard")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FlowLiveActivityPhaseCaption(phase: context.state.phase, isStale: context.isStale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                FlowLiveActivityBrandMark(height: 12)
            } compactTrailing: {
                FlowLiveActivityTrailingGlyph(phase: context.state.phase, isStale: context.isStale)
            } minimal: {
                // The minimal slot is a tiny circle; a short wordmark keeps
                // the natural ratio without overflowing its bounds.
                FlowLiveActivityBrandMark(height: 6)
            }
            .widgetURL(context.isStale ? Self.reconnectURL : nil)
            .keylineTint(Color(red: 0.35, green: 0.55, blue: 1.0))
        }
    }
}

// MARK: - Views

private struct FlowLiveActivityLockScreenView: View {
    let phase: FlowActivityAttributes.ContentState.Phase
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            FlowLiveActivityBrandMark(height: 10.4)
            VStack(alignment: .leading, spacing: 4) {
                Text("OSGKeyboard")
                    .font(.headline)
                FlowLiveActivityPhaseCaption(phase: phase, isStale: isStale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FlowLiveActivityTrailingGlyph(phase: phase, isStale: isStale)
        }
        // A stale activity means the host process is gone — never advertise
        // "Voice session active" for a dead session; grey the card instead.
        .opacity(isStale ? 0.55 : 1)
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
    var isStale: Bool = false

    var body: some View {
        if isStale {
            Image(systemName: "bolt.slash.circle")
                .foregroundStyle(.secondary)
        } else {
            phaseGlyph
        }
    }

    @ViewBuilder
    private var phaseGlyph: some View {
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
    var isStale: Bool = false

    var body: some View {
        if isStale {
            Image(systemName: "bolt.slash.circle")
                .foregroundStyle(.secondary)
        } else {
            phaseLabel
        }
    }

    @ViewBuilder
    private var phaseLabel: some View {
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
    var isStale: Bool = false

    var body: some View {
        if isStale {
            // Host process is gone — be honest about it and turn the card
            // into a recovery entry point (tap deep-links to startflow).
            Text("Session disconnected · tap to reconnect")
        } else {
            phaseCaption
        }
    }

    @ViewBuilder
    private var phaseCaption: some View {
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
