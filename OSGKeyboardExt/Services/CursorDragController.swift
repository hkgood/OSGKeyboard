// CursorDragController.swift
// OSGKeyboard · Keyboard Extension
//
// Cursor-drag hint chrome and batched caret moves via textDocumentProxy.

import UIKit
import OSGKeyboardShared

@MainActor
final class CursorDragController {
    private let state: KeyboardState
    private let adjustTextPosition: (Int) -> Void
    private weak var parentView: UIView?

    private var cursorDragHintLabel: UILabel?
    private var pendingHorizontalCursorSteps = 0
    private var pendingVerticalCursorSteps = 0
    private var cursorMoveFlushScheduled = false
    private let cursorLineHaptic = UIImpactFeedbackGenerator(style: .light)

    private static let cursorVerticalChunkSize = 20

    init(
        state: KeyboardState,
        adjustTextPosition: @escaping (Int) -> Void
    ) {
        self.state = state
        self.adjustTextPosition = adjustTextPosition
    }

    func install(on view: UIView) {
        parentView = view
        let hint = UILabel()
        hint.text = ExtL10n.string("keyboard.cursorDrag.centerHint")
        hint.font = .systemFont(ofSize: 22, weight: .medium)
        hint.textColor = UIColor.label.withAlphaComponent(0.10)
        hint.textAlignment = .center
        hint.numberOfLines = 1
        hint.adjustsFontSizeToFitWidth = true
        hint.minimumScaleFactor = 0.7
        hint.isUserInteractionEnabled = false
        hint.isHidden = true
        hint.alpha = 0
        view.addSubview(hint)
        cursorDragHintLabel = hint
        layoutChrome()
    }

    func layoutChrome() {
        guard let view = parentView else { return }
        cursorDragHintLabel?.frame = view.bounds
    }

    func setCursorDragActive(_ active: Bool) {
        state.cursorDragActive = active
        updateCursorDragWash(active: active)
    }

    func moveCursorHorizontally(by steps: Int) {
        guard steps != 0 else { return }
        pendingHorizontalCursorSteps += steps
        scheduleCursorMoveFlush()
    }

    func moveCursorVertically(by steps: Int) {
        guard steps != 0 else { return }
        pendingVerticalCursorSteps += steps
        scheduleCursorMoveFlush()
    }

    private func updateCursorDragWash(active: Bool) {
        if active {
            cursorLineHaptic.prepare()
        }
        layoutChrome()
        guard let hint = cursorDragHintLabel else { return }
        if active {
            hint.isHidden = false
            UIView.animate(withDuration: 0.12) { hint.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.12, animations: { hint.alpha = 0 }) { [weak self] _ in
                guard let self, !self.state.cursorDragActive else { return }
                hint.isHidden = true
            }
        }
    }

    private func scheduleCursorMoveFlush() {
        guard !cursorMoveFlushScheduled else { return }
        cursorMoveFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            guard let self else { return }
            self.cursorMoveFlushScheduled = false

            let horizontal = self.pendingHorizontalCursorSteps
            let vertical = self.pendingVerticalCursorSteps
            self.pendingHorizontalCursorSteps = 0
            self.pendingVerticalCursorSteps = 0

            if horizontal != 0 {
                OSGLog.keyboardExt.info("adjustTextPosition h=\(horizontal)")
                self.adjustTextPosition(horizontal)
            }

            if vertical != 0 {
                self.applyVerticalCursorSteps(vertical)
            }

            if self.pendingHorizontalCursorSteps != 0 || self.pendingVerticalCursorSteps != 0 {
                self.scheduleCursorMoveFlush()
            }
        }
    }

    private func applyVerticalCursorSteps(_ steps: Int) {
        let direction = steps > 0 ? 1 : -1
        var remaining = abs(steps)
        let chunk = Self.cursorVerticalChunkSize

        while remaining > 0 {
            adjustTextPosition(direction * chunk)
            cursorLineHaptic.impactOccurred()
            cursorLineHaptic.prepare()
            remaining -= 1
        }
    }
}
