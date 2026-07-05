// CursorDragPad.swift
// OSGKeyboard · Keyboard Extension
//
// SwiftUI layout wrapper for a UIKit pan recognizer. SwiftUI gestures
// can be unreliable in keyboard-extension hosting views; keeping the
// recognizer in UIKit preserves the existing layout while avoiding that
// failure mode.

import SwiftUI
import UIKit
import os

private let cursorDragLog = Logger(subsystem: "com.osgkeyboard.ios", category: "CursorDrag")

struct CursorDragPad: UIViewRepresentable {
    let enabled: Bool
    let onPressingChanged: (Bool) -> Void
    let moveHorizontal: (Int) -> Void
    let moveVertical: (Int) -> Void

    func makeUIView(context: Context) -> CursorDragPadUIView {
        cursorDragLog.info("makeUIView (enabled=\(enabled))")
        let view = CursorDragPadUIView()
        view.coordinator = context.coordinator
        view.isPadEnabled = enabled
        return view
    }

    func updateUIView(_ uiView: CursorDragPadUIView, context: Context) {
        context.coordinator.onPressingChanged = onPressingChanged
        context.coordinator.moveHorizontal = moveHorizontal
        context.coordinator.moveVertical = moveVertical
        uiView.isPadEnabled = enabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPressingChanged: onPressingChanged,
            moveHorizontal: moveHorizontal,
            moveVertical: moveVertical
        )
    }

    final class Coordinator {
        var onPressingChanged: (Bool) -> Void
        var moveHorizontal: (Int) -> Void
        var moveVertical: (Int) -> Void

        init(
            onPressingChanged: @escaping (Bool) -> Void,
            moveHorizontal: @escaping (Int) -> Void,
            moveVertical: @escaping (Int) -> Void
        ) {
            self.onPressingChanged = onPressingChanged
            self.moveHorizontal = moveHorizontal
            self.moveVertical = moveVertical
        }
    }
}

final class CursorDragPadUIView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: CursorDragPad.Coordinator?

    var isPadEnabled = true {
        didSet {
            isUserInteractionEnabled = isPadEnabled
            applyIdleTint()
        }
    }

    // MARK: - Pad tint
    // MUST stay non-zero. When embedded via `UIViewRepresentable`, a fully
    // transparent (alpha 0) background makes SwiftUI's host treat the region
    // as empty pass-through space and the pad stops receiving touches. A tiny
    // alpha (just above UIKit's 0.01 hit-test threshold) keeps the pad fully
    // draggable while remaining imperceptible.
    //
    // The keyboard surface itself is transparent (system chrome shows
    // through), so there is no fixed colour to match; `systemGray4` tracks
    // the system keyboard's grey in both light and dark and, at ~2% alpha,
    // blends invisibly. `withAlphaComponent` on a dynamic colour can freeze
    // the current trait, so resolve per-trait to stay appearance-adaptive.
    private static let padTint = UIColor { traits in
        UIColor.systemGray4.resolvedColor(with: traits).withAlphaComponent(0.02)
    }
    private static var idleTint: UIColor { padTint }
    private static var activeTint: UIColor { padTint }

    private func applyIdleTint() {
        backgroundColor = isPadEnabled ? Self.idleTint : .clear
    }

    private var lastTranslation = CGPoint.zero
    private var horizontalCarry: CGFloat = 0
    private var verticalCarry: CGFloat = 0
    private var didFireBeginHaptic = false
    /// Once the finger clears the dead zone, lock to one axis so slight
    /// diagonal jitter does not flip between horizontal and vertical steps.
    private var lockedAxis: LockedAxis?

    private enum LockedAxis {
        case horizontal
        case vertical
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.idleTint
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let size = "\(Int(bounds.width))x\(Int(bounds.height))"
        cursorDragLog.info("didMoveToWindow size=\(size, privacy: .public) attached=\(self.window != nil)")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self {
            cursorDragLog.debug("hitTest inside pad")
        }
        return hit
    }

    // Raw touch delivery drives the "drag mode" state so a static hold
    // (which a pan recognizer ignores until the finger moves) already
    // switches the keyboard into cursor-drag chrome.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isPadEnabled else { return }
        backgroundColor = Self.activeTint
        coordinator?.onPressingChanged(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        applyIdleTint()
        coordinator?.onPressingChanged(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        applyIdleTint()
        coordinator?.onPressingChanged(false)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isPadEnabled, let coordinator else { return }

        switch gesture.state {
        case .began:
            resetGestureState()
            backgroundColor = Self.activeTint
            coordinator.onPressingChanged(true)
            cursorDragLog.info("pan began")
        case .changed:
            handlePanChanged(gesture, coordinator: coordinator)
        case .ended, .cancelled, .failed:
            resetGestureState()
            applyIdleTint()
            coordinator.onPressingChanged(false)
        default:
            break
        }
    }

    private func handlePanChanged(
        _ gesture: UIPanGestureRecognizer,
        coordinator: CursorDragPad.Coordinator
    ) {
        let translation = gesture.translation(in: self)
        let delta = CGPoint(
            x: translation.x - lastTranslation.x,
            y: translation.y - lastTranslation.y
        )
        lastTranslation = translation

        let deadZone: CGFloat = 6
        guard max(abs(translation.x), abs(translation.y)) > deadZone else { return }

        if !didFireBeginHaptic {
            didFireBeginHaptic = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        if lockedAxis == nil {
            lockedAxis = abs(translation.x) >= abs(translation.y) ? .horizontal : .vertical
        }

        switch lockedAxis {
        case .horizontal:
            horizontalCarry += delta.x
            let threshold = stepThreshold(for: translation.x)
            let steps = consumeCarry(&horizontalCarry, threshold: threshold)
            if steps != 0 {
                coordinator.moveHorizontal(steps)
            }
        case .vertical:
            verticalCarry += delta.y
            let threshold = stepThreshold(for: translation.y) * Self.verticalSensitivityDamping
            let steps = consumeCarry(&verticalCarry, threshold: threshold)
            if steps != 0 {
                coordinator.moveVertical(steps)
            }
        case .none:
            break
        }
    }

    private func resetGestureState() {
        lastTranslation = .zero
        horizontalCarry = 0
        verticalCarry = 0
        didFireBeginHaptic = false
        lockedAxis = nil
    }

    /// Vertical steps move in large character chunks, so require more finger
    /// travel per step than horizontal to keep them from firing too fast.
    /// Higher = less sensitive.
    private static let verticalSensitivityDamping: CGFloat = 2.6

    /// Farther drag means a smaller threshold and faster stepping,
    /// capped so long swipes remain controllable.
    private func stepThreshold(for totalAxisDistance: CGFloat) -> CGFloat {
        let deadZone: CGFloat = 6
        let accelerated = max(0, abs(totalAxisDistance) - deadZone)
        let progress = min(1, accelerated / 100)
        return 12 - progress * 7
    }

    private func consumeCarry(_ carry: inout CGFloat, threshold: CGFloat) -> Int {
        guard threshold > 0 else { return 0 }
        let steps = Int(carry / threshold)
        if steps != 0 {
            carry -= CGFloat(steps) * threshold
        }
        return steps
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
