// GlobeInputModeButton.swift
// OSGKeyboard · Keyboard Extension
//
// System "next keyboard" (🌐) control. Registering
// `handleInputModeList(from:with:)` for all touch events lets UIKit provide
// native tap-to-advance and long-press input-mode selection without retaining
// a transient `UIEvent`. SwiftUI draws the shared native key chrome while a
// transparent `UIButton` owns touch delivery.

import SwiftUI
import UIKit
import OSGKeyboardShared

struct GlobeInputModeButton: UIViewRepresentable {
    @ObservedObject var state: KeyboardState
    @Binding var isPressed: Bool

    func makeUIView(context: Context) -> GlobeInputModeButtonView {
        let view = GlobeInputModeButtonView()
        view.onHighlightChanged = { isPressed = $0 }
        view.setInputModeController(state.inputModeController)
        return view
    }

    func updateUIView(_ uiView: GlobeInputModeButtonView, context: Context) {
        uiView.onHighlightChanged = { isPressed = $0 }
        uiView.setInputModeController(state.inputModeController)
    }

    static func dismantleUIView(_ uiView: GlobeInputModeButtonView, coordinator: Void) {
        uiView.onHighlightChanged = nil
        uiView.setInputModeController(nil)
    }
}

/// SwiftUI wrapper that frames the UIKit globe button and wires it to the
/// shared `KeyboardState` action hooks. Used on both iPad voice and typing
/// surfaces; iPhone relies on the system-provided switch below the keyboard.
/// Default 44×30 remains available for previews; bottom action rows pass an
/// explicit width / height so the key shares their complete geometry.
struct SystemGlobeKey: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette
    @ObservedObject var state: KeyboardState
    @State private var isPressed = false

    var width: CGFloat = 44
    var height: CGFloat = 30

    var body: some View {
        ZStack {
            NativeKeyboardKeySurface(
                isPressed: isPressed,
                fill: NativeKeyboardKeyColors.fill(for: colorScheme),
                pressedFill: NativeKeyboardKeyColors.pressedFill(for: colorScheme),
                border: palette.divider,
                cornerRadius: KeyboardChromeLayout.actionKeyCornerRadius
            ) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
                    .accessibilityHidden(true)
            }

            GlobeInputModeButton(state: state, isPressed: $isPressed)
                .accessibilityLabel(ExtL10n.text("keyboard.nextKeyboardA11y"))
                .accessibilityHint(ExtL10n.text("keyboard.nextKeyboardA11yHint"))
        }
        .frame(width: width, height: height)
    }
}

final class GlobeInputModeButtonView: UIButton {
    var onHighlightChanged: ((Bool) -> Void)?

    /// UIKit controls do not retain action targets, but keeping this explicitly
    /// weak documents and enforces the keyboard controller ownership boundary.
    private weak var inputModeController: UIInputViewController?
    private let inputModeAction = #selector(UIInputViewController.handleInputModeList(from:with:))

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            onHighlightChanged?(isHighlighted)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        // SwiftUI renders the icon, fill, border, shadow, and pressed state.
        // This UIKit layer stays transparent and handles only system gestures.
        backgroundColor = .clear
        isExclusiveTouch = true
        accessibilityTraits = .keyboardKey
    }

    func setInputModeController(_ controller: UIInputViewController?) {
        guard inputModeController !== controller else { return }
        if let inputModeController {
            removeTarget(
                inputModeController,
                action: inputModeAction,
                for: .allTouchEvents
            )
        }
        inputModeController = controller
        if let controller {
            addTarget(
                controller,
                action: inputModeAction,
                for: .allTouchEvents
            )
        }
    }
}
