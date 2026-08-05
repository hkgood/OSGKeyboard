// TypingKeyTouchPad.swift
// OSGKeyboard · Keyboard Extension
//
// Grid-level UIKit touch tracking for the typing surface:
// Down highlight → Move reselect → Up commit (letters / space / return),
// delete repeats on down, Shift holds while the gesture owns it.

import SwiftUI
import UIKit
import OSGKeyboardShared

struct TypingKeyTouchPad: UIViewRepresentable {
    var layout: TypingKeyLayout
    var hapticIntensity: KeyboardHapticIntensity
    var onHighlightChange: (String?) -> Void
    var onCommit: (TypingKeyHitTarget) -> Void
    var onDeleteFire: () -> Void
    var onShiftBegan: () -> Void
    var onShiftEnded: () -> Void

    func makeUIView(context: Context) -> TypingKeyTouchPadUIView {
        let view = TypingKeyTouchPadUIView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: TypingKeyTouchPadUIView, context: Context) {
        context.coordinator.parent = self
        uiView.layoutModel = layout
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator {
        var parent: TypingKeyTouchPad
        private var activeKeyID: String?
        private var gestureOwnsShift = false
        private var deleteRepeatTask: Task<Void, Never>?
        private var deleteRepeatStartedAt: Date?
        private var isDeleteRepeating = false

        init(parent: TypingKeyTouchPad) {
            self.parent = parent
        }

        func handleBegan(at point: CGPoint) {
            resetDeleteRepeat()
            gestureOwnsShift = false
            guard let key = hit(at: point) else {
                setHighlight(nil)
                return
            }
            activate(key)
        }

        func handleMoved(at point: CGPoint) {
            let key = hit(at: point)
            if key?.id == activeKeyID { return }

            if activeBehavior == .deleteRepeat {
                stopDeleteRepeat()
            }

            if let key {
                activate(key)
            } else {
                // Outside plane: clear highlight; Shift stays held until ended.
                setHighlight(nil)
                activeKeyID = nil
            }
        }

        func handleEnded(at point: CGPoint) {
            // Outside the key plane → cancel (no commit), per accuracy plan.
            let key = hit(at: point)
            stopDeleteRepeat()

            defer {
                setHighlight(nil)
                activeKeyID = nil
                finishShiftIfNeeded()
            }

            guard let key else { return }

            switch key.behavior {
            case .commitOnRelease:
                parent.onCommit(key)
            case .deleteRepeat:
                // Already fired on down / while held.
                break
            case .shiftHold:
                // endShiftHold decides tap vs hold-with-type.
                break
            }
        }

        func handleCancelled() {
            stopDeleteRepeat()
            setHighlight(nil)
            activeKeyID = nil
            finishShiftIfNeeded()
        }

        // MARK: - Internals

        private var activeBehavior: TypingKeyTouchBehavior? {
            guard let activeKeyID else { return nil }
            return parent.layout.key(id: activeKeyID)?.behavior
        }

        private func hit(at point: CGPoint) -> TypingKeyHitTarget? {
            let layout = parent.layout
            return KeyHitTesting.hitTarget(
                rawTouch: point,
                targets: layout.keys,
                keyPlaneBounds: layout.keyPlaneBounds,
                horizontalGap: layout.horizontalGap,
                verticalGap: layout.verticalGap,
                hitWeights: layout.hitWeights
            )
        }

        private func activate(_ key: TypingKeyHitTarget) {
            activeKeyID = key.id
            setHighlight(key.id)
            playFeedback(for: key)

            switch key.behavior {
            case .commitOnRelease:
                break
            case .deleteRepeat:
                parent.onDeleteFire()
                startDeleteRepeat()
            case .shiftHold:
                if !gestureOwnsShift {
                    gestureOwnsShift = true
                    parent.onShiftBegan()
                }
            }
        }

        private func setHighlight(_ id: String?) {
            parent.onHighlightChange(id)
        }

        private func playFeedback(for key: TypingKeyHitTarget) {
            let role: KeyboardHapticKeyRole
            let isDelete: Bool
            switch key.behavior {
            case .deleteRepeat:
                role = .delete
                isDelete = true
            case .shiftHold:
                role = .modifier
                isDelete = false
            case .commitOnRelease:
                isDelete = false
                if key.id.hasPrefix("bottom.") {
                    role = key.id == TypingKeyLayoutBuilder.BottomKeyID.pageSwitch.rawValue
                        ? .modifier
                        : .action
                } else if ["123", "#+=", "ABC"].contains(key.label) {
                    role = .modifier
                } else {
                    role = .character
                }
            }
            TypingKeyFeedback.play(
                role: role,
                intensity: parent.hapticIntensity,
                isDelete: isDelete
            )
        }

        private func startDeleteRepeat() {
            stopDeleteRepeat()
            isDeleteRepeating = true
            deleteRepeatStartedAt = Date()
            deleteRepeatTask = Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: UInt64(RepeatingDeleteTiming.initialDelay * 1_000_000_000)
                )
                guard !Task.isCancelled, self.isDeleteRepeating else { return }
                let anchor = self.deleteRepeatStartedAt ?? Date()
                while !Task.isCancelled, self.isDeleteRepeating {
                    // Match RepeatingPressButton: sound/haptic then action each tick.
                    TypingKeyFeedback.play(
                        role: .delete,
                        intensity: self.parent.hapticIntensity,
                        isDelete: true
                    )
                    self.parent.onDeleteFire()
                    let elapsed = Date().timeIntervalSince(anchor)
                    let wait = RepeatingDeleteTiming.interval(for: elapsed)
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            }
        }

        private func stopDeleteRepeat() {
            isDeleteRepeating = false
            deleteRepeatStartedAt = nil
            deleteRepeatTask?.cancel()
            deleteRepeatTask = nil
        }

        private func resetDeleteRepeat() {
            stopDeleteRepeat()
        }

        private func finishShiftIfNeeded() {
            guard gestureOwnsShift else { return }
            gestureOwnsShift = false
            parent.onShiftEnded()
        }
    }
}

final class TypingKeyTouchPadUIView: UIView {
    weak var coordinator: TypingKeyTouchPad.Coordinator?
    var layoutModel = TypingKeyLayout(
        keys: [],
        keyPlaneBounds: .zero,
        horizontalGap: 6,
        verticalGap: 7,
        bottomRowMinY: 0
    )

    /// Same trick as CursorDragPad: non-zero alpha so SwiftUI hosting does
    /// not treat the pad as pass-through.
    private static let padTint = UIColor { traits in
        UIColor.systemGray4.resolvedColor(with: traits).withAlphaComponent(0.02)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.padTint
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleMoved(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        coordinator?.handleEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.handleCancelled()
    }
}
