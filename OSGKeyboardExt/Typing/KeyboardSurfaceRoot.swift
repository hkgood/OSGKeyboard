// KeyboardSurfaceRoot.swift
// OSGKeyboard · Keyboard Extension
//
// Switches between voice and typing surfaces driven by KeyboardState.surface.

import SwiftUI
import OSGKeyboardShared

struct KeyboardSurfaceRoot: View {
    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController

    var onInsert: (String) -> Void
    var onDeleteBackward: () -> Void

    /// Height is deliberately independent of the surface: the voice surface
    /// adopts the typing surface's content-driven height and parks the surplus
    /// above its action cluster, so switching surfaces never resizes the
    /// keyboard. Keeping this a single expression is what guarantees it.
    static func height(
        for surface: KeyboardState.Surface,
        isIPad: Bool = false,
        width: CGFloat = 0
    ) -> CGFloat {
        TypingSurfaceMetrics.contentHeight(isIPad: isIPad, width: width)
    }

    var body: some View {
        Group {
            switch state.surface {
            case .voice:
                KeyboardRootView(
                    state: state,
                    typing: typing,
                    onInsert: onInsert
                )
            case .typing:
                TypingRootView(
                    state: state,
                    typing: typing,
                    onInsert: onInsert,
                    onDeleteBackward: onDeleteBackward
                )
            case .ai:
                AIKeyboardView(
                    state: state,
                    typing: typing,
                    onInsert: onInsert
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.surface)
        .onChange(of: state.surface) { _, newSurface in
            if newSurface != .typing {
                typing.leaveTypingMode()
            }
        }
    }
}
