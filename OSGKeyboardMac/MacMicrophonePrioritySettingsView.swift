// MacMicrophonePrioritySettingsView.swift
// OSGKeyboard · Mac

import SwiftUI

struct MacMicrophonePrioritySettingsView: View {
    @Environment(\.themePalette) private var palette

    private let store: MicrophonePriorityStore
    let language: AppUILanguage

    @State private var configuration: MicrophonePriorityConfiguration
    @State private var availableIDs = Set<String>()
    @State private var isRefreshing = false
    @State private var discoveryError: String?

    init(defaults: UserDefaults, language: AppUILanguage) {
        let store = MicrophonePriorityStore(defaults: defaults)
        self.store = store
        self.language = language
        _configuration = State(initialValue: store.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text(MacL10n.string("microphonePriority.instructions", language: language))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(
                            MacL10n.string("microphonePriority.refresh", language: language),
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, MacMetrics.settingsCardInset)
            .padding(.vertical, Spacing.xs)

            if configuration.prioritized.isEmpty, !isRefreshing {
                Divider().padding(.horizontal, MacMetrics.settingsCardInset)
                Text(MacL10n.string("microphonePriority.empty", language: language))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, MacMetrics.settingsCardInset)
                    .padding(.vertical, Spacing.sm)
            } else {
                ForEach(Array(configuration.prioritized.enumerated()), id: \.element.id) { index, device in
                    Divider().padding(.horizontal, MacMetrics.settingsCardInset)
                    priorityRow(device, index: index)
                        .draggable(device.id)
                        .dropDestination(for: String.self) { sourceIDs, location in
                            guard let sourceID = sourceIDs.first else { return false }
                            return move(
                                sourceID: sourceID,
                                relativeTo: device.id,
                                placeAfter: location.y > MacMetrics.settingsRowMinHeight / 2
                            )
                        }
                }
            }

            if !configuration.excluded.isEmpty {
                Divider().padding(.horizontal, MacMetrics.settingsCardInset)
                Text(MacL10n.string("microphonePriority.excluded", language: language))
                    .font(MacSettingsType.sectionTitle)
                    .foregroundStyle(palette.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, MacMetrics.settingsCardInset)
                    .padding(.top, Spacing.sm)

                ForEach(configuration.excluded) { device in
                    excludedRow(device)
                }
            }

            if let discoveryError {
                Divider().padding(.horizontal, MacMetrics.settingsCardInset)
                Label(discoveryError, systemImage: "exclamationmark.triangle.fill")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.warning)
                    .padding(.horizontal, MacMetrics.settingsCardInset)
                    .padding(.vertical, Spacing.sm)
            }
        }
        .task { await refresh() }
    }

    private func priorityRow(
        _ device: MicrophonePriorityDevice,
        index: Int
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Text("\(index + 1)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 20)
            Image(systemName: systemImage(for: device.kind))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(MacSettingsType.rowLabel)
                    .foregroundStyle(palette.textPrimary)
                Text(
                    MacL10n.string(
                        availableIDs.contains(device.id)
                            ? "microphonePriority.connected"
                            : "microphonePriority.disconnected",
                        language: language
                    )
                )
                .font(TypeStyle.caption)
                .foregroundStyle(
                    availableIDs.contains(device.id) ? palette.accent : palette.textTertiary
                )
            }
            Spacer(minLength: Spacing.sm)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(palette.textTertiary)
                .help(MacL10n.string("microphonePriority.dragHelp", language: language))
            Button {
                exclude(device.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(MacL10n.string("microphonePriority.exclude", language: language))
        }
        .padding(.horizontal, MacMetrics.settingsCardInset)
        .frame(minHeight: MacMetrics.settingsRowMinHeight)
        .contentShape(Rectangle())
    }

    private func excludedRow(_ device: MicrophonePriorityDevice) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage(for: device.kind))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 22)
            Text(device.name)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Spacing.sm)
            Button(MacL10n.string("microphonePriority.restore", language: language)) {
                configuration.restore(id: device.id)
                store.save(configuration)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, MacMetrics.settingsCardInset)
        .frame(minHeight: MacMetrics.settingsRowMinHeight)
    }

    private func move(
        sourceID: String,
        relativeTo targetID: String,
        placeAfter: Bool
    ) -> Bool {
        guard
            sourceID != targetID,
            let sourceIndex = configuration.prioritized.firstIndex(where: { $0.id == sourceID }),
            let targetIndex = configuration.prioritized.firstIndex(where: { $0.id == targetID })
        else { return false }

        configuration.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex + (placeAfter ? 1 : 0)
        )
        store.save(configuration)
        return true
    }

    private func exclude(_ id: String) {
        configuration.exclude(id: id)
        store.save(configuration)
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let devices = try await Task.detached(priority: .userInitiated) {
                try MacAudioInputDevices.available()
            }.value
            let available = devices.map(\.priorityDevice)
            availableIDs = Set(available.map(\.id))
            configuration = store.mergeAndSave(available: available)
            discoveryError = nil
        } catch {
            discoveryError = error.localizedDescription
        }
    }

    private func systemImage(for kind: MicrophoneDeviceKind) -> String {
        switch kind {
        case .builtIn: return "laptopcomputer"
        case .bluetooth: return "airpodspro"
        case .usb: return "cable.connector"
        case .wired: return "headphones"
        case .virtual: return "waveform.path"
        case .other: return "mic"
        }
    }
}
