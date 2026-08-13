// KeyboardSurfaceRoot.swift
// OSGKeyboard · Keyboard Extension
//
// Switches between voice and typing surfaces driven by KeyboardState.surface.

import SwiftUI
import OSGKeyboardShared

struct KeyboardSurfaceRoot: View {
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var keyboardTabSelectionNamespace

    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController

    var onInsert: (String) -> Void
    var onDeleteBackward: () -> Void

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

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
        ZStack {
            Group {
                switch state.surface {
                case .voice:
                    KeyboardRootView(
                        state: state,
                        typing: typing,
                        onInsert: wrappedInsert
                    )
                case .typing:
                    TypingRootView(
                        state: state,
                        typing: typing,
                        onInsert: wrappedInsert,
                        onDeleteBackward: wrappedDeleteBackward
                    )
                case .ai:
                    AIKeyboardView(
                        state: state,
                        typing: typing,
                        onInsert: wrappedInsert
                    )
                }
            }
            .opacity(state.clipboardOverlay == .none ? 1 : 0)
            .allowsHitTesting(state.clipboardOverlay == .none)

            // Match every surface's outer chrome so the panel title / X sit in
            // the same slot as the logo + clipboard chip (not 4 pt higher).
            clipboardOverlayLayer
                .padding(.top, TypingSurfaceMetrics.outerPaddingTop)
                .padding(.bottom, TypingSurfaceMetrics.outerPaddingBottom)
        }
        // Overlays are siblings of the surfaces, so the palette has to be
        // injected here or they fall back to the environment's dark default.
        .environment(\.themePalette, palette)
        // The input surfaces are replaced when switching tabs. Keep one
        // namespace above that switch so the selected glass pill can morph
        // between the outgoing and incoming top-control instances.
        .environment(\.keyboardTabSelectionNamespace, keyboardTabSelectionNamespace)
        // Bottom-anchored on purpose: UIKit hands the input view a container up
        // to the full screen height while the keyboard slides in, and centering
        // a fixed-height surface in it parks the whole keyboard above the
        // visible slot — which reads as a blank keyboard whenever that frame
        // lingers (a slow Universal Clipboard read, a system alert).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeInOut(duration: 0.15), value: state.surface)
        .onChange(of: state.surface) { _, newSurface in
            if newSurface != .typing {
                typing.leaveTypingMode()
            }
        }
    }

    private func wrappedInsert(_ text: String) {
        if !text.isEmpty {
            state.noteUserDidInputText()
        }
        onInsert(text)
    }

    private func wrappedDeleteBackward() {
        state.noteUserDidInputText()
        onDeleteBackward()
    }

    @ViewBuilder
    private var clipboardOverlayLayer: some View {
        if !state.canShowClipboardEntry {
            EmptyView()
        } else {
            switch state.clipboardOverlay {
            case .none:
                EmptyView()
            case .enableGuide:
                ClipboardEnableGuideView(
                    onClose: state.dismissClipboardOverlay,
                    onOpenSettings: {
                        state.dismissClipboardOverlay()
                        state.openClipboardSettings()
                    }
                )
            case .historyPanel:
                ClipboardHistoryPanelView(
                    history: ClipboardHistoryStore.shared,
                    onClose: state.dismissClipboardOverlay,
                    onClear: state.clearClipboardHistory,
                    onInsert: { state.insertClipboardText($0) },
                    onDelete: { state.deleteClipboardHistoryEntry($0) },
                    pastePermissionHint: nil
                )
            }
        }
    }
}
