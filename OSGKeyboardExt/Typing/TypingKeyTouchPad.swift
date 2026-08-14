// TypingKeyTouchPad.swift
// OSGKeyboard · Keyboard Extension
//
// Grid-level UIKit touch tracking for the typing surface:
// Down highlight → Move reselect → Up commit (letters / space / return),
// overlapping fingers commit in press order, delete repeats on down,
// Shift holds while that finger owns it.

import SwiftUI
import UIKit
import OSGKeyboardShared

struct TypingKeyTouchPad: UIViewRepresentable {
    var layout: TypingKeyLayout
    var hapticIntensity: KeyboardHapticIntensity
    var onHighlightChange: (Set<String>) -> Void
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
        private let tracker = TypingTouchTracker()
        private var deleteRepeatTask: Task<Void, Never>?
        private var deleteRepeatStartedAt: Date?
        private var isDeleteRepeating = false

        init(parent: TypingKeyTouchPad) {
            self.parent = parent
        }

        func handleBegan(id: ObjectIdentifier, at point: CGPoint) {
            apply(tracker.began(id: id, key: hit(at: point)))
        }

        func handleMoved(id: ObjectIdentifier, at point: CGPoint) {
            apply(tracker.moved(id: id, key: hit(at: point)))
        }

        func handleEnded(id: ObjectIdentifier, at point: CGPoint) {
            apply(tracker.ended(id: id, key: hit(at: point)))
        }

        func handleCancelled(id: ObjectIdentifier) {
            apply(tracker.cancelled(id: id))
        }

        // MARK: - Internals

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

        private func apply(_ effects: TypingTouchEffects) {
            if effects.stopDeleteRepeat {
                stopDeleteRepeat()
            }
            for key in effects.commits {
                parent.onCommit(key)
            }
            if let key = effects.playFeedback {
                playFeedback(for: key)
            }
            if effects.deleteFire {
                parent.onDeleteFire()
            }
            if effects.startDeleteRepeat {
                startDeleteRepeat()
            }
            if effects.beginShift {
                parent.onShiftBegan()
            }
            if effects.endShift {
                parent.onShiftEnded()
            }
            parent.onHighlightChange(tracker.highlightedKeyIDs)
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
        isMultipleTouchEnabled = true
        isExclusiveTouch = true
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in Self.sorted(touches) {
            coordinator?.handleBegan(id: ObjectIdentifier(touch), at: touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in Self.sorted(touches) {
            coordinator?.handleMoved(id: ObjectIdentifier(touch), at: touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in Self.sorted(touches) {
            coordinator?.handleEnded(id: ObjectIdentifier(touch), at: touch.location(in: self))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in Self.sorted(touches) {
            coordinator?.handleCancelled(id: ObjectIdentifier(touch))
        }
    }

    private static func sorted(_ touches: Set<UITouch>) -> [UITouch] {
        touches.sorted { $0.timestamp < $1.timestamp }
    }
}
