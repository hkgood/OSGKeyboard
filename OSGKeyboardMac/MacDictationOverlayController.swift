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
    /// The pill is a fixed size, so the panel never needs to resize while the
    /// transcript grows — see `MacDictationOverlayView.panelSize`.
    private let panelSize = MacDictationOverlayView.panelSize

    // MARK: - User-draggable position (persisted across launches)

    /// True once the user has dragged the HUD; suppresses the default
    /// bottom-center snap so the panel stays where the user placed it.
    private var hasCustomPosition = false
    /// Stored as center-X + bottom-left Y so the anchor stays stable while the
    /// pill grows / shrinks with the live transcript (symmetric resize).
    private var customCenterX: CGFloat = 0
    private var customOriginY: CGFloat = 0
    /// Cursor + window origin captured at the start of a manual drag, so we can
    /// follow the absolute cursor and stay immune to the window moving under it.
    private var dragCursorStart: NSPoint?
    private var dragWindowStart: NSPoint?

    private static let hasCustomPositionKey = "mac.overlay.hasCustomPosition"
    private static let centerXKey = "mac.overlay.centerX"
    private static let originYKey = "mac.overlay.originY"

    private init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.hasCustomPositionKey) {
            hasCustomPosition = true
            customCenterX = CGFloat(defaults.double(forKey: Self.centerXKey))
            customOriginY = CGFloat(defaults.double(forKey: Self.originYKey))
        }
    }

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

        // Waveform / app name / copy refresh through the view's own
        // `@ObservedObject` binding. Re-driving them from `objectWillChange`
        // used to reassign `rootView` and force a synchronous relayout ~20×/s
        // (the level timer's cadence), which deadlocked AppKit layout during
        // the state storm that fires when the hold-to-talk key is released.

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
        // Once per show, not per state change: picks up an appearance or UI
        // language switch made since the pill was last visible.
        refreshContent(viewModel: viewModel)
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
        host.frame = NSRect(origin: .zero, size: panelSize)
        hosting = host

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
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
        // Background dragging can't move a non-activating panel; we drive the
        // drag ourselves from a SwiftUI DragGesture (see `dragMoved`).
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
            MacDictationOverlayView(
                viewModel: viewModel,
                onDragChanged: { [weak self] in self?.dragMoved() },
                onDragEnded: { [weak self] in self?.dragEnded() },
                onResetPosition: { [weak self] in self?.resetPositionToDefault() }
            )
            .macSystemPalette()
            .environment(\.locale, viewModel.config.uiLanguage.swiftUILocale)
            .preferredColorScheme(MacAppearancePreference.current.colorScheme)
        )
    }

    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panelSize
        // Respect the user's dragged spot; otherwise snap to bottom-center.
        let desired: NSPoint
        if hasCustomPosition {
            desired = NSPoint(x: customCenterX - size.width / 2, y: customOriginY)
        } else {
            desired = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + bottomMargin
            )
        }
        panel.setFrameOrigin(clampedOrigin(desired, size: size, in: visible))
    }

    /// Keep the panel fully inside the screen's visible frame so a dragged /
    /// restored position can never strand it off-screen (e.g. after a display
    /// or resolution change).
    private func clampedOrigin(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        guard visible.width >= size.width, visible.height >= size.height else {
            return origin
        }
        let x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        let y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    /// Follows the absolute cursor while dragging. Reading `NSEvent.mouseLocation`
    /// (screen coordinates) instead of the gesture's local translation avoids the
    /// feedback loop you'd get from moving the window the gesture lives in.
    private func dragMoved() {
        guard let panel else { return }
        let cursor = NSEvent.mouseLocation
        if dragCursorStart == nil {
            dragCursorStart = cursor
            dragWindowStart = panel.frame.origin
        }
        guard let cursorStart = dragCursorStart, let windowStart = dragWindowStart else { return }
        let target = NSPoint(
            x: windowStart.x + (cursor.x - cursorStart.x),
            y: windowStart.y + (cursor.y - cursorStart.y)
        )
        let size = panel.frame.size
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        panel.setFrameOrigin(visible.map { clampedOrigin(target, size: size, in: $0) } ?? target)
    }

    /// Persist the dragged spot as center-X + bottom-left Y.
    private func dragEnded() {
        dragCursorStart = nil
        dragWindowStart = nil
        guard let panel else { return }
        customCenterX = panel.frame.midX
        customOriginY = panel.frame.origin.y
        hasCustomPosition = true
        persistPosition()
    }

    /// Double-clicking the pill clears the custom spot and returns it to the
    /// default bottom-center.
    private func resetPositionToDefault() {
        hasCustomPosition = false
        clearPersistedPosition()
        reposition()
    }

    private func persistPosition() {
        let defaults = UserDefaults.standard
        defaults.set(hasCustomPosition, forKey: Self.hasCustomPositionKey)
        defaults.set(Double(customCenterX), forKey: Self.centerXKey)
        defaults.set(Double(customOriginY), forKey: Self.originYKey)
    }

    private func clearPersistedPosition() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.hasCustomPositionKey)
        defaults.removeObject(forKey: Self.centerXKey)
        defaults.removeObject(forKey: Self.originYKey)
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
