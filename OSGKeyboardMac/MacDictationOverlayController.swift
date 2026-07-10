// MacDictationOverlayController.swift
// OSGKeyboard · Mac
//
// Owns a borderless, non-activating floating NSPanel that hosts the
// dictation HUD. Shown for any recording path (hotkey, menu bar, main
// window) and dismissed after a short success beat when processing ends.

import AppKit
import Combine
import SwiftUI

@MainActor
final class MacDictationOverlayController {
    static let shared = MacDictationOverlayController()

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    /// Keeps the pill visible briefly after a successful delivery.
    private var showingCompletion = false
    private var wasBusy = false

    private let bottomMargin: CGFloat = 36
    private let fallbackSize = NSSize(width: 400, height: 52)

    private init() {}

    func start(observing viewModel: MacDictationViewModel) {
        guard cancellables.isEmpty else { return }

        Publishers.CombineLatest3(
            viewModel.$isRecording,
            viewModel.$isPreparingToRecord,
            viewModel.$isProcessing
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] recording, preparing, processing in
            self?.handleBusyChange(
                recording: recording,
                preparing: preparing,
                processing: processing,
                viewModel: viewModel
            )
        }
        .store(in: &cancellables)

        // Keep waveform / app name / copy fresh while visible.
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel?.isVisible == true else { return }
                self.refreshContent(viewModel: viewModel)
                self.resizeToFit()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    private func handleBusyChange(
        recording: Bool,
        preparing: Bool,
        processing: Bool,
        viewModel: MacDictationViewModel
    ) {
        let busy = recording || preparing || processing

        if busy {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            showingCompletion = false
            wasBusy = true
            present(viewModel: viewModel)
            return
        }

        // Transition: busy → idle. Flash a short "done" state, then hide.
        if wasBusy {
            wasBusy = false
            showingCompletion = true
            present(viewModel: viewModel)
            scheduleHide()
            return
        }

        if !showingCompletion {
            hideImmediately()
        }
    }

    private func present(viewModel: MacDictationViewModel) {
        ensurePanel(viewModel: viewModel)
        refreshContent(viewModel: viewModel)
        resizeToFit()
        reposition()

        guard let panel else { return }
        if panel.isVisible {
            // Already up — still bump to front in case another space stole it.
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanel(viewModel: MacDictationViewModel) {
        if panel != nil { return }

        let host = NSHostingView(rootView: makeRoot(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: fallbackSize)
        hosting = host

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fallbackSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above normal floating windows so the HUD stays visible over browsers /
        // full-screen apps, without going as high as the screen saver.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel
    }

    private func refreshContent(viewModel: MacDictationViewModel) {
        hosting?.rootView = makeRoot(viewModel: viewModel)
    }

    private func makeRoot(viewModel: MacDictationViewModel) -> AnyView {
        AnyView(
            MacDictationOverlayView(viewModel: viewModel)
                .macSystemPalette()
                .environment(\.locale, viewModel.config.uiLanguage.swiftUILocale)
                .preferredColorScheme(MacAppearancePreference.current.colorScheme)
        )
    }

    private func resizeToFit() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let width = fitting.width.isFinite && fitting.width > 1
            ? min(max(fitting.width, 300), 520)
            : fallbackSize.width
        let height = fitting.height.isFinite && fitting.height > 1
            ? max(fitting.height, fallbackSize.height)
            : fallbackSize.height
        var frame = panel.frame
        let midX = frame.midX
        frame.size = NSSize(width: width, height: height)
        if midX.isFinite {
            frame.origin.x = midX - width / 2
        }
        panel.setFrame(frame, display: true)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + bottomMargin
        )
        panel.setFrameOrigin(origin)
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.showingCompletion = false
            self?.hideAnimated()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }

    private func hideImmediately() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        showingCompletion = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func hideAnimated() {
        guard let panel, panel.isVisible else {
            hideImmediately()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel?.orderOut(nil)
                self?.panel?.alphaValue = 1
            }
        })
    }
}
