// KeyboardRootView.swift
// OSGKeyboard · Keyboard Extension
//
// The single SwiftUI view that backs the keyboard. Shows status text,
// the record button, waveform (when active), and a settings shortcut.

import SwiftUI

public struct KeyboardRootView: View {
    public enum Phase: Equatable {
        case idle
        case recording
        case processing
        case error(String)
    }

    public let phase: Phase
    public let level: Double          // 0...1, used while recording
    public let onPressBegan: () -> Void
    public let onPressEnded: () -> Void
    public let onTap: () -> Void
    public let onOpenSettings: () -> Void

    public init(
        phase: Phase,
        level: Double,
        onPressBegan: @escaping () -> Void,
        onPressEnded: @escaping () -> Void,
        onTap: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.phase = phase
        self.level = level
        self.onPressBegan = onPressBegan
        self.onPressEnded = onPressEnded
        self.onTap = onTap
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ZStack {
            // frosted glass background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            HStack {
                Spacer()
                statusLine
                Spacer()
                recordButton
                Spacer()
                settingsButton
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 56)
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch phase {
            case .idle:
                Text("Hold to talk")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            case .recording:
                HStack(spacing: 6) {
                    WaveformView(level: level, barCount: 7, color: .red)
                    Text("Recording…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
            case .processing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Polishing…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            case .error(let msg):
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordButton: some View {
        RecordButton(
            phase: recordState,
            onPressBegan: onPressBegan,
            onPressEnded: onPressEnded,
            onTap: onTap
        )
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open OSGKeyboard settings"))
    }

    private var recordState: RecordButton.Phase {
        switch phase {
        case .idle:        return .idle
        case .recording:   return .recording
        case .processing:  return .processing
        case .error(let s): return .error(s)
        }
    }
}
