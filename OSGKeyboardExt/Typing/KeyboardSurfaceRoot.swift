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

    static var voiceHeight: CGFloat { KeyboardRootView.totalHeight }
    static var typingHeight: CGFloat { TypingRootView.totalHeight }

    static func height(for surface: KeyboardState.Surface) -> CGFloat {
        switch surface {
        case .voice: return voiceHeight
        case .typing: return typingHeight
        }
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
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.surface)
        .onChange(of: state.surface) { _, newSurface in
            if newSurface == .voice {
                typing.leaveTypingMode()
            }
        }
    }
}
