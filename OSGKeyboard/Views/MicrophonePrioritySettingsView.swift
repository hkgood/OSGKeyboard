// MicrophonePrioritySettingsView.swift
// OSGKeyboard · iOS
//
// Device-local microphone routing. iOS only exposes currently connected
// input ports, so previously seen ports remain visible as offline entries.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

struct MicrophonePrioritySettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    private let store = MicrophonePriorityStore()
    @State private var configuration = MicrophonePriorityStore().load()
    @State private var availableIDs = Set<String>()
    @State private var isRefreshing = false
    @State private var discoveryError: String?

    var body: some View {
        List {
            Section {
                if configuration.prioritized.isEmpty {
                    Text("settings.microphonePriority.empty")
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(configuration.prioritized) { device in
                        microphoneRow(device)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: exclude)
                }
            } header: {
                Text("settings.microphonePriority.enabled")
            } footer: {
                Text("settings.microphonePriority.footer")
            }

            if !configuration.excluded.isEmpty {
                Section("settings.microphonePriority.excluded") {
                    ForEach(configuration.excluded) { device in
                        HStack(spacing: Spacing.sm) {
                            microphoneLabel(device)
                            Spacer(minLength: Spacing.sm)
                            Button("settings.microphonePriority.restore") {
                                restore(device.id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if let discoveryError {
                Section {
                    Label(discoveryError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(palette.warning)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.microphonePriority.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("settings.microphonePriority.refresh")
            }
        }
        .task { await refresh() }
    }

    private func microphoneRow(_ device: MicrophonePriorityDevice) -> some View {
        HStack(spacing: Spacing.sm) {
            microphoneLabel(device)
            Spacer(minLength: Spacing.sm)
            Text(LocalizedStringKey(
                availableIDs.contains(device.id)
                    ? "settings.microphonePriority.connected"
                    : "settings.microphonePriority.disconnected"
            ))
            .font(.caption)
            .foregroundStyle(
                availableIDs.contains(device.id) ? palette.accent : palette.textTertiary
            )
        }
    }

    private func microphoneLabel(_ device: MicrophonePriorityDevice) -> some View {
        Label {
            Text(device.name)
                .foregroundStyle(palette.textPrimary)
        } icon: {
            Image(systemName: systemImage(for: device.kind))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func move(fromOffsets: IndexSet, toOffset: Int) {
        configuration.move(fromOffsets: fromOffsets, toOffset: toOffset)
        store.save(configuration)
    }

    private func exclude(atOffsets offsets: IndexSet) {
        configuration.exclude(atOffsets: offsets)
        store.save(configuration)
    }

    private func restore(_ id: String) {
        configuration.restore(id: id)
        store.save(configuration)
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let available = try await FlowAudioSessionCoordinator.shared.discoverMicrophones()
            availableIDs = Set(available.map(\.id))
            configuration = store.mergeAndSave(available: available)
            discoveryError = nil
        } catch {
            discoveryError = error.localizedDescription
        }
    }

    private func systemImage(for kind: MicrophoneDeviceKind) -> String {
        switch kind {
        case .builtIn: return "iphone"
        case .bluetooth: return "airpodspro"
        case .usb: return "cable.connector"
        case .wired: return "headphones"
        case .virtual: return "waveform.path"
        case .other: return "mic"
        }
    }
}
