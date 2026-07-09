// MacLocalASRModelSettingsView.swift
// OSGKeyboard · Mac
//
// Local ASR model catalog, download progress, MLX path, and bias diagnostics.

import AppKit
import SwiftUI

@MainActor
final class MacLocalASRModelSettingsViewModel: ObservableObject {
    @Published var catalog: LocalASRCatalogDocument?
    @Published var selectedModelId: String = MacLocalASRPreferences.selectedModelId
    @Published var installProgress = LocalASRModelInstallProgress.idle
    @Published var diagnosticsSnapshot = LocalASRBiasDiagnosticsStore.load()
    @Published var statusMessage = ""
    @Published var isInstalling = false
    @Published var isDownloadPaused = false

    var onLocalModelStateChanged: (() -> Void)?

    private let manager = LocalASRModelManager.shared
    private var progressPollTask: Task<Void, Never>?

    deinit {
        progressPollTask?.cancel()
    }

    func reload() {
        catalog = try? LocalASRModelCatalog.loadBundled()
        if let catalog {
            let manifest = LocalASRInstalledManifestIO.load(defaultModelId: catalog.defaultModelId)
            selectedModelId = manifest.selectedModelId.isEmpty
                ? MacLocalASRPreferences.selectedModelId
                : manifest.selectedModelId
        }
        diagnosticsSnapshot = LocalASRBiasDiagnosticsStore.load()
        onLocalModelStateChanged?()
    }

    func isInstalled(_ model: LocalASRModelDefinition) -> Bool {
        MacLocalASRService.isModelInstalled(model)
    }

    func isInstallingModel(_ model: LocalASRModelDefinition) -> Bool {
        isInstalling && installProgress.activeItemId == model.id
    }

    func installedDiskUsage(_ model: LocalASRModelDefinition) -> String? {
        guard model.installKind == .archive,
              let relative = model.installRelativePath,
              isInstalled(model) else { return nil }
        let dir = LocalASRModelInstallState.installDirectory(for: relative)
        let bytes = LocalASRModelInstallState.directoryByteCount(at: dir)
        guard bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func currentRuntime(in catalog: LocalASRCatalogDocument) -> LocalASRRuntimeDefinition? {
        LocalASRModelCatalog.runtime(for: LocalASRModelCatalog.currentRuntimePlatform(), in: catalog)
    }

    func isRuntimeInstalled(_ runtime: LocalASRRuntimeDefinition) -> Bool {
        LocalASRModelInstallState.isRuntimeInstalled(runtime)
    }

    func selectModel(_ modelId: String) {
        guard let catalog, !isInstalling else { return }
        selectedModelId = modelId
        MacLocalASRPreferences.selectedModelId = modelId
        var manifest = LocalASRInstalledManifestIO.load(defaultModelId: catalog.defaultModelId)
        manifest.selectedModelId = modelId
        manifest.updatedAt = Date()
        try? LocalASRInstalledManifestIO.save(manifest)
        onLocalModelStateChanged?()
    }

    func installModel(_ model: LocalASRModelDefinition) {
        guard let catalog, !isInstalling else { return }
        statusMessage = ""
        isInstalling = true
        isDownloadPaused = false
        startProgressPolling()
        Task {
            do {
                try await manager.installModel(model, catalog: catalog)
                installProgress = await manager.currentProgress()
                selectModel(model.id)
                statusMessage = MacL10n.string("mac.localASR.installDone")
            } catch {
                installProgress = await manager.currentProgress()
                statusMessage = error.localizedDescription
            }
            isInstalling = false
            isDownloadPaused = false
            stopProgressPolling()
            reload()
        }
    }

    func pauseDownload() {
        Task {
            do {
                try await manager.pauseDownload()
                isDownloadPaused = true
                installProgress = await manager.currentProgress()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func resumeDownload() {
        Task {
            do {
                try await manager.resumeDownload()
                isDownloadPaused = false
                installProgress = await manager.currentProgress()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func deleteModel(_ model: LocalASRModelDefinition) {
        guard let catalog, !isInstalling else { return }
        Task {
            do {
                try await manager.deleteModel(model, catalog: catalog)
                statusMessage = MacL10n.string("mac.localASR.deleteDone")
                reload()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func revealModelInFinder(_ model: LocalASRModelDefinition) {
        guard let relative = model.installRelativePath else { return }
        let url = LocalASRModelInstallState.installDirectory(for: relative)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens (creating if needed) the model's shared subfolder so the user can
    /// drop in manually-converted weights (used by the MLX model).
    func revealModelFolder(_ model: LocalASRModelDefinition) {
        guard let relative = model.installRelativePath else { return }
        let url = LocalASRModelInstallState.installDirectory(for: relative)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func revealStorageRoot() {
        let url = LocalASRModelInstallState.rootDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func progressLabel(for progress: LocalASRModelInstallProgress, language: AppUILanguage) -> String {
        let phaseKey: String
        switch progress.phase {
        case .downloading: phaseKey = "mac.localASR.phase.downloading"
        case .paused: phaseKey = "mac.localASR.phase.paused"
        case .extracting: phaseKey = "mac.localASR.phase.extracting"
        case .validating: phaseKey = "mac.localASR.phase.validating"
        case .finalizing: phaseKey = "mac.localASR.phase.finalizing"
        case .failed: phaseKey = "mac.localASR.phase.failed"
        case .completed: phaseKey = "mac.localASR.phase.completed"
        case .idle: return progress.message
        }
        let phase = MacL10n.string(phaseKey, language: language)
        if let received = progress.bytesReceived, let total = progress.bytesTotal, total > 0 {
            let recv = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
            let tot = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "\(phase) · \(progress.message) (\(recv) / \(tot))"
        }
        return "\(phase) · \(progress.message)"
    }

    private func startProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let current = await manager.currentProgress()
                await MainActor.run {
                    self.installProgress = current
                    self.isDownloadPaused = current.phase == .paused
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = nil
    }

    func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct MacLocalASRModelSettingsView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @StateObject private var modelVM = MacLocalASRModelSettingsViewModel()
    @Environment(\.themePalette) private var palette

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    var body: some View {
        Group {
            if let catalog = modelVM.catalog {
                modelPickerSection(catalog: catalog)
                runtimeSection(catalog: catalog)
            } else {
                Text(MacL10n.string("mac.localASR.catalogMissing", language: lang))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .onAppear {
            modelVM.onLocalModelStateChanged = { viewModel.bumpLocalModelRevision() }
            modelVM.reload()
        }
    }

    private func modelPickerSection(catalog: LocalASRCatalogDocument) -> some View {
        Section {
            ForEach(catalog.models) { model in
                modelRow(model)
            }

            if modelVM.isInstalling,
               modelVM.installProgress.phase == .extracting
                || modelVM.installProgress.phase == .validating
                || modelVM.installProgress.phase == .finalizing {
                ProgressView(value: modelVM.installProgress.fraction) {
                    Text(modelVM.progressLabel(for: modelVM.installProgress, language: lang))
                        .font(TypeStyle.caption)
                }
            }

            if !modelVM.statusMessage.isEmpty {
                Text(modelVM.statusMessage)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Button(MacL10n.string("mac.localASR.openStorage", language: lang)) {
                modelVM.revealStorageRoot()
            }
        } header: {
            Text(MacL10n.string("mac.localASR.models", language: lang))
        } footer: {
            Text(MacL10n.string("mac.localASR.modelsDesc", language: lang))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func runtimeSection(catalog: LocalASRCatalogDocument) -> some View {
        Group {
            if let runtime = modelVM.currentRuntime(in: catalog) {
                Section {
                    LabeledContent(runtime.displayName) {
                        Text(
                            modelVM.isRuntimeInstalled(runtime)
                                ? MacL10n.string("mac.localASR.installed", language: lang)
                                : MacL10n.string("mac.localASR.notInstalled", language: lang)
                        )
                    }
                    Text(MacL10n.string("mac.localASR.runtimeDesc", language: lang))
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                } header: {
                    Text(MacL10n.string("mac.localASR.runtime", language: lang))
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: LocalASRModelDefinition) -> some View {
        let installed = modelVM.isInstalled(model)
        let selected = modelVM.selectedModelId == model.id
        let installing = modelVM.isInstallingModel(model)

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top) {
                Button {
                    modelVM.selectModel(model.id)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? palette.accent : palette.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .foregroundStyle(palette.textPrimary)
                            Text(modelSubtitle(model, installed: installed))
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(modelVM.isInstalling)

                Spacer()

                modelRowActions(model: model, installed: installed, installing: installing)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func modelRowActions(
        model: LocalASRModelDefinition,
        installed: Bool,
        installing: Bool
    ) -> some View {
        if installing {
            HStack(spacing: Spacing.sm) {
                circularInstallProgress(for: model)
                if modelVM.installProgress.phase == .downloading
                    || modelVM.installProgress.phase == .paused {
                    Button {
                        if modelVM.isDownloadPaused {
                            modelVM.resumeDownload()
                        } else {
                            modelVM.pauseDownload()
                        }
                    } label: {
                        Image(systemName: modelVM.isDownloadPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(
                        modelVM.isDownloadPaused
                            ? MacL10n.string("mac.localASR.resume", language: lang)
                            : MacL10n.string("mac.localASR.pause", language: lang)
                    )
                }
            }
        } else if model.installKind == .manual {
            Button(MacL10n.string("mac.localASR.openFolder", language: lang)) {
                modelVM.revealModelFolder(model)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if installed {
            Button(MacL10n.string("mac.localASR.delete", language: lang), role: .destructive) {
                modelVM.deleteModel(model)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button(MacL10n.string("mac.localASR.download", language: lang)) {
                modelVM.installModel(model)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func circularInstallProgress(for model: LocalASRModelDefinition) -> some View {
        let fraction: Double = {
            if modelVM.installProgress.phase == .downloading || modelVM.installProgress.phase == .paused,
               let received = modelVM.installProgress.bytesReceived,
               let total = modelVM.installProgress.bytesTotal,
               total > 0 {
                return min(1, max(0, Double(received) / Double(total)))
            }
            return modelVM.installProgress.fraction
        }()
        return ZStack {
            Circle()
                .stroke(palette.textTertiary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: fraction)
            if modelVM.installProgress.phase == .paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel(modelVM.progressLabel(for: modelVM.installProgress, language: lang))
    }

    private func modelSubtitle(_ model: LocalASRModelDefinition, installed: Bool) -> String {
        let size = modelVM.formattedSize(model.sizeBytes)
        let hotword = model.supportsHotwords
            ? MacL10n.string("mac.localASR.hotwordsYes", language: lang)
            : MacL10n.string("mac.localASR.hotwordsNo", language: lang)
        let state = installed
            ? MacL10n.string("mac.localASR.installed", language: lang)
            : MacL10n.string("mac.localASR.notInstalled", language: lang)
        if let usage = modelVM.installedDiskUsage(model) {
            return "\(size) · \(hotword) · \(state) · \(usage)"
        }
        return "\(size) · \(hotword) · \(state)"
    }

    private var diagnosticsSection: some View {
        Section {
            if let snapshot = modelVM.diagnosticsSnapshot {
                LabeledContent(MacL10n.string("mac.localASR.diagBackend", language: lang)) {
                    Text(snapshot.backendLabel ?? "—")
                }
                LabeledContent(MacL10n.string("mac.localASR.diagUserTerms", language: lang)) {
                    Text("\(snapshot.diagnostics.userTermCount)")
                }
                LabeledContent(MacL10n.string("mac.localASR.diagBuiltinTerms", language: lang)) {
                    Text("\(snapshot.diagnostics.builtinTermCount)")
                }
                LabeledContent(MacL10n.string("mac.localASR.diagHotwords", language: lang)) {
                    Text("\(snapshot.hotwordCount)")
                }
                LabeledContent(MacL10n.string("mac.localASR.diagPrompt", language: lang)) {
                    Text("\(snapshot.promptBiasLength)")
                }
                if snapshot.diagnostics.truncated {
                    Label(
                        snapshot.diagnostics.truncationReason ?? MacL10n.string("mac.localASR.diagTruncated", language: lang),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.warning)
                }
                Text(snapshot.diagnostics.selectedSources.joined(separator: ", "))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text(MacL10n.string("mac.localASR.diagEmpty", language: lang))
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            Text(MacL10n.string("mac.localASR.diagnostics", language: lang))
        } footer: {
            Text(MacL10n.string("mac.localASR.diagnosticsDesc", language: lang))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }
}
