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

    // MARK: - User-draggable position (persisted across launches)

    /// True once the user has dragged the HUD; suppresses the default
    /// bottom-center snap so the panel stays where the user placed it.
    private var hasCustomPosition = false
    /// Stored as center-X + bottom-left Y so the anchor stays stable while the
    /// pill grows / shrinks with the live transcript (symmetric resize).
    private var customCenterX: CGFloat = 0
    private var customOriginY: CGFloat = 0
    /// The origin we last set programmatically (kept for clamping / bookkeeping).
    private var lastProgrammaticOrigin: NSPoint?
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

    private func resizeToFit() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        // Bounds include the 32pt horizontal transparent margin around the pill
        // (16 per side) that gives the shadow room, so the pill body itself
        // still spans ~300–520.
        let width = fitting.width.isFinite && fitting.width > 1
            ? min(max(fitting.width, 332), 552)
            : fallbackSize.width
        let height = fitting.height.isFinite && fitting.height > 1
            ? max(fitting.height, fallbackSize.height)
            : fallbackSize.height
        var frame = panel.frame
        // Grow / shrink around the anchor center so the pill stays put: the
        // dragged center when custom, otherwise its current center.
        let targetMidX = hasCustomPosition ? customCenterX : frame.midX
        frame.size = NSSize(width: width, height: height)
        if targetMidX.isFinite {
            frame.origin.x = targetMidX - width / 2
        }
        if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            frame.origin = clampedOrigin(frame.origin, size: frame.size, in: visible)
        }
        lastProgrammaticOrigin = frame.origin
        panel.setFrame(frame, display: true)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
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
        let origin = clampedOrigin(desired, size: size, in: visible)
        lastProgrammaticOrigin = origin
        panel.setFrameOrigin(origin)
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
        let origin = visible.map { clampedOrigin(target, size: size, in: $0) } ?? target
        lastProgrammaticOrigin = origin
        panel.setFrameOrigin(origin)
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
        resizeToFit()
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
