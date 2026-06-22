// DictationCaptureView.swift
// OSGKeyboard · Main App
//
// Host-app recording surface for keyboard handoff.
// Uses the shared `LiveDictationController` — the same entry point as
// the keyboard preview sheet.

import SwiftUI
import OSGKeyboardShared

@MainActor
final class DictationSessionCoordinator: ObservableObject {
    @Published var isPresenting: Bool = false

    func present() {
        isPresenting = true
    }

    func dismiss() {
        isPresenting = false
    }
}

struct DictationCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    @ObservedObject var coordinator: DictationSessionCoordinator
    @StateObject private var dictation = LiveDictationController()

    @State private var statusText: String = ""
    @State private var isSaving: Bool = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                Spacer()
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(palette.accent)

                Text(titleText)
                    .font(TypeStyle.title2)
                    .foregroundStyle(palette.textPrimary)

                Text(statusText)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)

                ProgressView(value: dictation.level, total: 1.0)
                    .tint(palette.accent)
                    .padding(.horizontal, Spacing.lg)
                Spacer()

                HStack(spacing: Spacing.sm) {
                    Button {
                        cancelAndClose()
                    } label: {
                        Text("common.cancel")
                            .secondaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    Button {
                        stopAndFinalize()
                    } label: {
                        Text("common.done")
                            .primaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || dictation.phase != .recording)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
        }
        .onAppear {
            statusText = AppL10n.string("dictation.status.ready")
            DictationBridge.setStatus(.requested)
            startRecording()
        }
        .onDisappear {
            dictation.stop()
        }
        .onChange(of: dictation.phase) { _, new in
            switch new {
            case .recording:
                DictationBridge.setStatus(.recording)
                statusText = config.isLocalEngine
                    ? AppL10n.string("dictation.status.listeningLive")
                    : AppL10n.string("dictation.status.listening")
            case .processing:
                DictationBridge.setStatus(.transcribing)
                statusText = AppL10n.string("dictation.status.processing")
            case .requestingPermission:
                statusText = AppL10n.string("dictation.status.requestingPermission")
            case .denied(let message):
                DictationBridge.setStatus(.error, message: message)
                statusText = message
            case .error(let message):
                DictationBridge.setStatus(.error, message: message)
                statusText = message
            case .idle:
                break
            }
        }
        .onChange(of: dictation.currentPartial) { _, new in
            guard config.isLocalEngine, !new.isEmpty else { return }
            statusText = new
        }
        .onChange(of: dictation.lastFinal) { _, new in
            guard !new.isEmpty else { return }
            saveAndClose(new)
        }
        .onChange(of: config.uiLanguage) { _, _ in
            refreshStatusForCurrentPhase()
        }
    }

    private var titleText: String {
        isSaving
            ? AppL10n.string("dictation.status.saving")
            : AppL10n.string("dictation.title")
    }

    private func startRecording() {
        Task { await dictation.start(localeId: config.localeId) }
    }

    private func stopAndFinalize() {
        dictation.stop()
        statusText = AppL10n.string("dictation.status.waitingResult")
    }

    private func cancelAndClose() {
        dictation.stop()
        DictationBridge.setStatus(.cancelled)
        coordinator.dismiss()
        dismiss()
    }

    private func saveAndClose(_ transcript: String) {
        guard !isSaving else { return }
        isSaving = true
        statusText = AppL10n.string("dictation.status.processing")
        Task {
            let delivered = transcript
            DictationBridge.storePendingTranscript(delivered, polishWarning: nil)
            coordinator.dismiss()
            dismiss()
        }
    }

    private func refreshStatusForCurrentPhase() {
        switch dictation.phase {
        case .idle:
            statusText = AppL10n.string("dictation.status.ready")
        case .recording:
            statusText = config.isLocalEngine
                ? AppL10n.string("dictation.status.listeningLive")
                : AppL10n.string("dictation.status.listening")
        case .processing:
            statusText = AppL10n.string("dictation.status.processing")
        case .requestingPermission:
            statusText = AppL10n.string("dictation.status.requestingPermission")
        case .denied(let message), .error(let message):
            statusText = message
        }
    }
}
